---
title: "2020/11/12 Dialog Paper Survey"
date: 2020-11-12T19:33:05+09:00
draft: false
---

なんか久しぶりに研究をしたくなってきた。
続くかわからないが(多分続かない)自分の興味のある対話システムについて論文を読んでいきたい。

## Hybrid Supervised Reinforced Model for Dialogue Systems

https://arxiv.org/pdf/2011.02243.pdf

- publish
  - 2020/11/4
- summary
  - タスク指向dialog systemのためのState TrackingとDecision Makingのハイブリッドモデル
  - Deep Recurrent Q-Networkをベースとする
  - non-reccurentなベースラインに対し良い結果

## Example Phrase Adaptation Method for Customized, Example-Based Dialog System Using User Data and Distributed Word Representations

https://www.jstage.jst.go.jp/article/transinf/E103.D/11/E103.D_2020EDP7066/_pdf

- publish
  - 2020/11
  - IEICE TRANS. INF. & SYST., VOL.E103–D, NO.11 
- summary
  - ユーザーの事前に収集したプロフィールの情報を対話の例文に埋め込んだ対話システム
  - 例文に埋め込むWordは、Word2Vecのベクトル加減算でそれっぽい方向に変化させる
  - 結果、より自然な会話を出せた

## Towards Topic-Guided Conversational Recommender System

https://arxiv.org/pdf/2010.04125.pdf

- publish
  - 2020/11
- summary
  - ユーザーにハイクオリティな商品をレコメンドする対話システムのデータセットの研究
  - 特徴
    - Topic Threadがある
    - 半自動で作られる
  - データセット
    - https://github.com/RUCAIBox/TG-ReDial
