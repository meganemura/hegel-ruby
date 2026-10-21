# Hegel for Ruby

[English README](README.md)

> [!IMPORTANT]
> **これは非公式のサードパーティ実装です。** Hegel プロジェクトと `libhegel`
> エンジンは Antithesis, LLC のものです。このリポジトリは Antithesis とも
> `hegeldev` organization とも関係がなく、先方のレビューや承認も受けていません。
>
> 公式実装は
> [Rust](https://github.com/hegeldev/hegel/tree/main/frontends/rust)、
> [Go](https://github.com/hegeldev/hegel-go)、
> [C++](https://github.com/hegeldev/hegel-cpp)、
> [TypeScript](https://github.com/hegeldev/hegel-typescript)、
> [Java](https://github.com/hegeldev/hegel-java)、
> [OCaml](https://github.com/hegeldev/hegel-ocaml) です。この gem の問題は
> 公式実装ではなく、このリポジトリに報告してください。

> [!NOTE]
> Hegel 自体はベータ版で、今後も互換性のない変更が入る予定です。
> <https://hegel.dev/compatibility> を参照してください。

Hegel は [Hypothesis](https://github.com/hypothesisworks/hypothesis) を土台にした
プロパティベーステストのフレームワークです。手で選んだ入力でテストを書く代わりに、
どの入力でも成り立つべき性質を書きます。Hegel は入力を生成して性質を破ろうとし、
失敗を見つけたら最小の反例まで縮めます。

この gem は、公式実装も使っているネイティブエンジン
[libhegel](https://hegel.dev/reference/libhegel) を
[`ffi`](https://github.com/ffi/ffi) gem 経由で同じプロセス内で動かします。
サーバーも Python も要りません。

## インストール

gem 名は [`hegeltest`](https://rubygems.org/gems/hegeltest) です。

```ruby
# Gemfile
gem "hegeltest", group: :test
```

require パスは `hegel`、名前空間は `Hegel` です。Bundler の自動 require のために
`require "hegeltest"` も使えます。

Ruby 3.4 以上が必要です。各プラットフォーム向け gem には対応する `libhegel` の
ビルドが同梱されているので、インストール時にコンパイルは不要で、エンジンを
別に用意する必要もありません。

| プラットフォーム | gem のプラットフォーム |
| --- | --- |
| Linux x64 | `x86_64-linux` |
| Linux arm64 | `aarch64-linux` |
| macOS arm64 | `arm64-darwin` |
| Windows x64 | `x64-mingw-ucrt` |
| Windows arm64 | `aarch64-mingw-ucrt` |

Hegel のメンテナーは、サードパーティによるリリースバイナリの再配布を認めています
([hegeldev/hegel-rust#411])。

すでに `Gemfile.lock` があるプロジェクトでは、もう一手間要ります。Bundler は
`bundle install` を実行したマシンのプラットフォームしか lock に足さないので、
Mac で作った lock には Linux が載りません。そのままだと Linux の CI で gem が
見つかりません。CI で使うプラットフォームを追加してください。

```bash
bundle lock --add-platform x86_64-linux
```

Intel Mac のように `libhegel` のビルドが公開されていないプラットフォームでは、
エンジンを自分でビルドし、`HEGEL_LIBHEGEL_PATH` にそのライブラリファイルか、
それを含むディレクトリを指定してください。同じ変数で、どのプラットフォームでも
同梱のエンジンの代わりにローカルビルドを使えます。

[hegeldev/hegel-rust#411]: https://github.com/hegeldev/hegel-rust/issues/411

### どの libhegel が入っているか

gem の各リリースは libhegel のリリースを 1 つ固定しています。インストール済みの
gem が固定しているバージョンは次のコマンドで確認できます。

```bash
ruby -rhegel -e 'puts Hegel::LIBHEGEL_VERSION'
```

[CHANGELOG](CHANGELOG.md) の各リリースの節は、エンジンの更新があればその内容から
始まり、そのエンジンのリリースノートにリンクしています。
[GitHub Releases](https://github.com/meganemura/hegel-ruby/releases) にも
同じ内容が載ります。

libhegel の新しいリリースが出ると、それに追従する pull request が作られます。
gem のバージョンとエンジンのバージョンは独立していて、gem のリリースには
エンジンの更新、Ruby コードの変更、またはその両方が含まれます。

## クイックスタート

```ruby
# spec/spec_helper.rb
require "hegel"

RSpec.configure do |config|
  config.include Hegel::Syntax::Methods
end
```

```ruby
# spec/my_sort_spec.rb
def my_sort(ls) = ls.sort.uniq # oops: uniq drops duplicates

RSpec.describe "my_sort" do
  it "matches the builtin sort" do
    Hegel.test do |tc|
      xs = tc.draw(arrays(integers))
      expect(my_sort(xs)).to eq(xs.sort)
    end
  end
end
```

このテストは失敗し、Hegel はバグを再現する最小の入力まで縮めます。
レポートは次のようになります。

```
Falsified after 11 test cases (0 discarded):

  xs = [0, 0]

To reproduce this failure, pass the blob below to Hegel.test:
    reproduce_failure: "AXicY2VgYGBkZOBiZEBhMAAAAd8AIQ=="
```

テストケースの数と blob は実行ごと、エンジンのリリースごとに変わります。
見るべきなのは縮めた値で、重複が 2 つあれば十分だとわかります。Hegel は
draw を書いた行を読んで値に `xs` という名前を付け、RSpec 自身の expectation
失敗を投げ直すので、RSpec は普段どおりの失敗として報告します。

`Hegel::Syntax::Methods` を include すると、FactoryBot の `create` のように
ジェネレーターを接頭辞なしで使えます。include しなくても
`Hegel::Generators.arrays(...)` として使えます。

独自のヘルパーを持つ example group にジェネレーター名を持ち込みたくない場合は、
タグを付けた group だけに include します。

```ruby
config.include Hegel::Syntax::Methods, :hegel
```

Hegel は値を命令的に draw するので、普通の Ruby メソッドで複数の draw を
プロパティ間で共有できます。メソッドの引数には、RuboCop の既定の命名規則に
合う説明的な名前を付けてください。

```ruby
def draw_sorted_pair(test_case)
  low = test_case.draw(integers(min_value: 0, max_value: 100))
  high = test_case.draw(integers(min_value: low, max_value: 200))
  [low, high]
end

Hegel.test do |tc|
  low, high = draw_sorted_pair(tc)
  expect(low).to be <= high
end
```

### Minitest

Hegel はテストフレームワークに何も要求しません。ジェネレーターのメソッドを
一度 include し、普通のテストの中にプロパティを書きます。

```ruby
# test/test_helper.rb
require "hegel"

class Minitest::Test
  include Hegel::Syntax::Methods
end
```

```ruby
# test/my_sort_test.rb
class MySortTest < Minitest::Test
  def test_matches_the_builtin_sort
    Hegel.test do |tc|
      xs = tc.draw(arrays(integers))
      assert_equal xs.sort, my_sort(xs)
    end
  end
end
```

Minitest は縮めたケースを、テストを書いた行での通常の assertion 失敗として
報告します。

```
1) Failure:
MySortTest#test_matches_the_builtin_sort [test/my_sort_test.rb:5]:
Expected: [0, 0]
  Actual: [0]
```

## ジェネレーター

| 種類 | ジェネレーター |
| --- | --- |
| 数値と真偽値 | `integers`, `floats`, `booleans` |
| 文字列とバイト列 | `text`, `characters`, `binary`, `from_regex` |
| コレクション | `arrays`, `sets`, `hashes`, `tuples` |
| 選択 | `just`, `sampled_from`, `one_of`, `optional` |
| 書式 | `emails`, `urls`, `domains`, `ip_addresses`, `uuids` |
| 日時 | `dates`, `times`, `datetimes` |
| 自作 | `composite`, `deferred` |

どれも `map` と `filter` で組み合わせられます。オプションはキーワード引数で、
`integers(min_value: 0, max_value: 9)` や `arrays(text, max_size: 5)` のように、
他の Hegel 実装と同じ名前を使います。オプションの組み合わせが不正な場合は、
ジェネレーターを作ったときではなく draw したときに例外になります。

## ステートフルテスト

入力 1 つではなく、操作の列で初めて出るバグもあります。操作を
`Hegel::StateMachine` のルールとして宣言すると、Hegel が次に実行するルールを選び、
途中で不変条件を確かめ、失敗をそれが再現する最短の操作列まで縮めます。

```ruby
class StackMachine < Hegel::StateMachine
  def initialize
    @stack = BoundedStack.new(3)
    @model = []
  end

  rule :push do |tc|
    x = tc.draw(integers(min_value: 0, max_value: 9))
    @stack.push(x)
    @model.push(x) if @model.size < 3
  end

  rule :pop do |tc|
    tc.assume(!@model.empty?)
    raise "pop disagreed" unless @stack.pop == @model.pop
  end

  invariant :size_agrees do
    raise "size disagreed" unless @stack.size == @model.size
  end
end

Hegel.test { |tc| Hegel::Stateful.run(StackMachine.new, tc) }
```

ルールの中の `tc.assume` は、テストケース全体を捨てるのではなく、そのルールだけを
却下して別のルールを選ばせます。`alloc` が返したハンドルを解放するなど、前のルールが
作った値を使うルールでは、値を `Hegel::Stateful::Pool` に入れて、そこから draw します。

すべての不変条件は最初のルールの前と最後のルールの後に実行されます。ルールの間では
エンジンが各不変条件をサンプリングします。毎回のルールの後に確かめたい不変条件は
`always_run: true` 付きで宣言してください。
`Hegel::Stateful.run(machine, tc, step_count: 50)` で 1 テストケースあたりの最大
ルール数を指定できます。既定は 50 です。

## 実行の設定

`Hegel.test` は次のキーワードを受け取ります。

| キーワード | 効果 |
| --- | --- |
| `profile` | 実行の出発点にする設定プロファイル。[プロファイル](#プロファイル)を参照 |
| `test_cases` | 生成するテストケースの数 |
| `seed` | ランダム生成のシード |
| `derandomize` | 生成を決定的にする |
| `verbosity` | エンジンの出力量。`:quiet` は失敗レポートも隠す |
| `phases` | 生成や縮小など、実行するエンジンのフェーズ |
| `suppress_health_check` | 無効にするヘルスチェック |
| `report_multiple_failures` | 異なる失敗をそれぞれ報告する。既定は `false` |
| `stop_on_first_failure` | `false` にすると `test_cases` を使い切ってから報告する |
| `print_blob` | `false` にすると失敗レポートから再現用の行を外す |
| `show_statistics` | `tc.event` と `tc.event_value` で記録した内容を実行の最後に表示する |
| `nondeterminism_strictness` | 再実行で振る舞いが変わるテストへの反応。`:quiet`、`:warn`、`:error` |
| `backend` | `:default`、または値を引くたびに外部のエントロピーを使う `:urandom`(Antithesis 向け) |
| `database_key` | このプロパティで example database を有効にする |
| `database` | example database のディレクトリ |
| `reproduce_failure` | レポートの blob から 1 つの失敗を再生する |

指定しなかったキーワードは、エンジンの設定プロファイルの値になります。これは
`hegel.toml` や `HEGEL_*` 環境変数で変えない限り libhegel 自身の既定値です。
CI サーバー上ではエンジンが `ci` プロファイルを使い、実行を決定的にして
example database を無効にします。

example database は失敗したケースを保存し、次回最初に再生します。
`database_key` で有効になり、`database` でディレクトリを選びます。

```ruby
Hegel.test(database_key: "my_sort matches the builtin sort") { |tc| ... }
```

プロパティごとに別のキーを付けてください。ディレクトリではなくキーで有効になる
理由は [ADR 0009](docs/adr/0009-turn-the-example-database-on-with-a-key.md) に
あります。

テストの中では、`tc.note` で失敗レポートに出すメッセージを記録でき、
`tc.target` で Hegel が探索を寄せる方向を指定できます。

`tc.event` と `tc.event_value` は、テストが狙ったケースに届いているかを確かめる
ためのものです。`show_statistics: true` にすると、各イベントが起きた割合と、
各値の分布の要約をエンジンが表示します。数値は実行ごとに変わります。

```ruby
Hegel.test(show_statistics: true) do |tc|
  xs = tc.draw(arrays(integers))
  tc.event("empty") if xs.empty?
  tc.event_value("size", xs.size)
end
```

```
Statistics (over 100 test cases):
  * empty: 6.0% of test cases
  * size: count 100, min 0, median 6, mean 7.99, p90 19, max 20
```

## プロファイル

プロファイルは名前の付いた設定の組です。エンジンは `development`、`ci`、
`workload` を同梱しており、`hegel.toml` でさらに定義できます。`profile:` を
渡すと 1 回の実行をそのプロファイルから始められ、独自のプロファイルは
`Hegel::Settings.register_profile` で登録できます。

```ruby
Hegel::Settings.register_profile("nightly", profile: "ci", test_cases: 10_000)

Hegel.test(profile: "nightly") { |tc| ... }
```

`Hegel.test` に渡したキーワードはプロファイルより優先されます。名前を指定した
プロファイルは既定のプロファイルを継承するので、設定していない項目は既定の
プロファイルから来ます。`Hegel::Settings.set_default_profile("nightly")` は
そのプロセスのすべての実行の既定にし、`set_default_profile("")` で解除します。
登録と既定はプロセス全体に効き、すでに始まった実行は変わりません。
`register_profile` は `database_key` を除く `Hegel.test` のキーワードを受け取ります。
プロファイルは `database_key` を持たないためです。また `Hegel.test` は常に
`report_multiple_failures` を渡すので、プロファイル側の値は使われません。
未知の名前は `Hegel::Error` になります。
[ADR 0028](docs/adr/0028-expose-settings-profiles-as-a-keyword-and-module-functions.md)
を参照してください。

## エージェント向けスキル

2 つのスキルを組み合わせて使います。Hegel のメンテナーによる公式の
[hegel-skill](https://github.com/hegeldev/hegel-skill) は、どの性質を探すか、
エージェントが書いたテストをどう確かめるかといった手法を教えるもので、
どの Hegel 実装でも使えます。[`skills/hegel-ruby`](skills/hegel-ruby/SKILL.md) は
Ruby の部分、つまりこの gem の API と RSpec・Minitest での使い方を足します。
両方をインストールしてください。

Claude Code では、それぞれのリポジトリをマーケットプレイスとして追加し、
プラグインをインストールします。

```
/plugin marketplace add hegeldev/hegel-skill
/plugin install hegel-skill@hegeldev
/plugin marketplace add meganemura/hegel-ruby
/plugin install hegel-ruby@meganemura
```

Codex などほかのエージェントでのインストール方法は、
[hegel-skill の README](https://github.com/hegeldev/hegel-skill#installation) を
参照してください。この gem のスキルは、同じ手順で
<https://github.com/meganemura/hegel-ruby/tree/main/skills/hegel-ruby> を指定すればインストールできます。

## 開発

```bash
bin/setup                        # 依存関係をインストール
bundle exec rake libhegel:fetch  # 固定したエンジンを SHA-256 で検証してダウンロード
bundle exec rake                 # カバレッジ付きのテストとリンター
bundle exec rake mutation        # ミューテーションテスト
bin/console                      # 対話プロンプト
```

`just` のレシピは同じ Rake タスクを呼ぶので、他の Hegel 実装で `just` を使っている
人は `just check`、`just test`、`just lint` をそのまま使えます。

CI は pull request と main への push ごとに、上の表のすべてのプラットフォームで
Ruby 3.4 と 4.0 のテストを実行します。

設計の記録は [docs/](docs/README.md) にあります。

### リリース

main へのマージで `lib/hegel/version.rb` が変わると、リリースが始まります。
Release ワークフローは `release` 環境の承認を待ち、承認されるとテストを実行し、
gem を RubyGems に公開し、タグ `v<version>` と GitHub Release を作ります。
リリースノートは [CHANGELOG.md](CHANGELOG.md) のそのバージョンの節から作られます。
[ADR 0024](docs/adr/0024-release-when-a-merge-changes-the-gem-version.md) を
参照してください。

## コントリビュート

バグ報告と pull request は <https://github.com/meganemura/hegel-ruby> へ。
コントリビューターは[行動規範](CODE_OF_CONDUCT.md)に従ってください。

## ライセンス

この gem は [MIT License](LICENSE.txt) で利用できます。

リリースされた gem には `libhegel` 自身のライセンス(MIT、copyright Antithesis, LLC)
も含まれます。各プラットフォーム向け gem はエンジンの隣に `NOTICE-libhegel.txt` を
同梱しており、その全文が入っています。
