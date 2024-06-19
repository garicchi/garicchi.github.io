---
title: "dotnet coreでRazorテンプレートからテキストを生成する"
date: 2024-06-19T19:40:38+09:00
slug: 2024-06-19-razor
type: posts
draft: false
categories:
  - computer
tags:
  - csharp
---

goでいう [text/template](https://pkg.go.dev/text/template)のように、
テンプレートから、オブジェクトを動的に当てはめてテキストを生成したいということがあります。

dotnetでいうと、ASP.NETがRazorテンプレートを使っているので、
似たようなことができそうですが、ASP.NET以外でRazorを使うのは少し難易度が高いです。

dotnet framework時代は[RazorEngine](https://antaris.github.io/RazorEngine/)というOSSがあったようで、これを使えばテンプレートから文字列生成をできたようです。

しかしRazorEngineはGithubの更新が7年前で、メンテナーを探していると公式サイトに書いてあり、nugetのパッケージはdotnet framework向けで、さらにセキュリティ警告が出ているようです。
自分の環境で試したところでは、dotnet coreのプロジェクトで動きませんでした。

おそらく、Roslynの登場で代替できるようになったからかと思うのですが、
Roslynで似たようなことをする例があまりなかったのでサンプルコードを作ってみました。

```cs
namespace Razor
{
    public abstract class TemplateBase
    {
        protected dynamic Model { get; set; } = default!;
        private StringBuilder StringBuilder = new();

        public void SetModel(dynamic model)
        {
            this.Model = model;
        }

        public void WriteLiteral(string literal)
        {
            StringBuilder.Append(literal);
        }

        public void Write(object obj)
        {
            StringBuilder.Append(obj.ToString());
        }

        public string GetGeneratedText()
        {
            return StringBuilder.ToString();
        }

        public virtual async Task ExecuteAsync()
        {
            await Task.Yield();
        }
    }
}

public record class RazorCompileResult
    {
        public required IEnumerable<Diagnostic> Diagnostics { get; init; }
        public required string? GeneratedText { get; init; }

        public bool IsSuccess => !Diagnostics.Any(x => x.Severity is DiagnosticSeverity.Error);
    }
    public class RazorTemplateCompileService
    {
        public static readonly HashSet<string> ReferencedAssemblies = new()
        {
            "System.Private.CoreLib",
            "System.Runtime",
            "Microsoft.CSharp"
        };

        private List<PortableExecutableReference> MetadataReferences { get; }

        private RazorProjectEngine Engine { get; }

        public RazorTemplateCompileService()
        {
            var metadatas = ReferencedAssemblies.Select(x => MetadataReference.CreateFromFile(Assembly.Load(x).Location)).ToList();
            metadatas.Add(MetadataReference.CreateFromFile(typeof(Razor.TemplateBase).GetTypeInfo().Assembly.Location));
            metadatas.Add(MetadataReference.CreateFromFile(typeof(DynamicObject).Assembly.Location));
            MetadataReferences = metadatas;
            var defaultConfig = RazorConfiguration.Default;
            var razorConfig = RazorConfiguration.Create(
                RazorLanguageVersion.Version_6_0,
                defaultConfig.ConfigurationName,
                defaultConfig.Extensions,
                defaultConfig.UseConsolidatedMvcViews);
            this.Engine = RazorProjectEngine.Create(razorConfig, RazorProjectFileSystem.Create("."), builder =>
            {
                builder.SetCSharpLanguageVersion(LanguageVersion.CSharp10);
            });
        }
        public async Task<RazorCompileResult> CompileAsync(string template, dynamic model)
        {
            var codeDoc = Engine.Process(RazorSourceDocument.Create(template, "myfile", Encoding.UTF8), null,
                new List<RazorSourceDocument>(),
                new List<TagHelperDescriptor>());
            var generatedCode = codeDoc.GetCSharpDocument().GeneratedCode;
            generatedCode = generatedCode.Replace("public class Template", "public class Template : TemplateBase");
            var tree = CSharpSyntaxTree.ParseText(generatedCode);

            var compilation = CSharpCompilation.Create("myassembly", new[] { tree }, this.MetadataReferences,
            options: new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary));
            using var memStream = new MemoryStream();
            var compileResult = compilation.Emit(memStream);
            if (!compileResult.Success)
            {
                return new RazorCompileResult
                {
                    Diagnostics = compileResult.Diagnostics,
                    GeneratedText = null
                };
            }
            memStream.Seek(0, SeekOrigin.Begin);
            var assembly = AssemblyLoadContext.Default.LoadFromStream(memStream);
            var instance = assembly.CreateInstance("Razor.Template");
            var templateClass = assembly.GetType("Razor.Template");
            ArgumentNullException.ThrowIfNull(templateClass);
            var methodSetModel = templateClass.GetMember(nameof(TemplateBase.SetModel)).First() as MethodInfo;
            ArgumentNullException.ThrowIfNull(methodSetModel);
            methodSetModel.Invoke(instance, [model]);
            var methodExecute = templateClass.GetMember(nameof(TemplateBase.ExecuteAsync)).First() as MethodInfo;
            ArgumentNullException.ThrowIfNull(methodExecute);
            var task = methodExecute.Invoke(instance, null) as Task;
            ArgumentNullException.ThrowIfNull(task);
            await task;

            var methodGetGeneratedText = templateClass.GetMember(nameof(TemplateBase.GetGeneratedText)).First() as MethodInfo;
            ArgumentNullException.ThrowIfNull(methodGetGeneratedText);
            var resultStr = methodGetGeneratedText.Invoke(instance, null) as string;
            ArgumentNullException.ThrowIfNull(resultStr);
            return new RazorCompileResult
            {
                Diagnostics = compileResult.Diagnostics,
                GeneratedText = resultStr
            };
        }
    }
```

dynamic型を使用するので、 `dotnet add package Microsoft.Csharp` が必要です
あとはこれをこんな感じで呼び出せば、

```cs

public class TestModel
{
    public required string Name { get; init; }
    public List<int> Hoge = new List<int> { 1, 2, 3 };
}

string template = @"
Hello, @Model.Name welcome
@foreach (var i in Model.Hoge) {
 <text>@(i)
</text>
}
to RazorEngine!";
var razor = new RazorTemplateCompileService();
var result = await razor.CompileAsync(template, new TestModel
{
    Name = "me!"
});
Console.WriteLine(result.GeneratedText);
```

こんな感じの出力を得られます

```
Hello, me! welcome
1
2
3
to RazorEngine!
```

下記サイトが参考になりました

- https://qiita.com/gushwell/items/fe71a0c751f37e8d6d52
- https://blogs.siliconorchid.com/post/coding-inspiration/razor-templating-with-roslyn/