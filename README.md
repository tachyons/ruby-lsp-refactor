# ruby-lsp-refactor

> **Beta software.** This gem is under active development. Refactorings may
> produce incorrect output in edge cases. A significant portion of the
> implementation was written with AI assistance — please review generated edits
> before committing them. Bug reports and corrections are very welcome.

A [ruby-lsp](https://github.com/Shopify/ruby-lsp) add-on that provides
AST-driven refactoring code actions natively inside any LSP-supported editor
(VS Code, Zed, Neovim, RubyMine, etc.).

All refactors are powered by the [Prism](https://github.com/ruby/prism) parser
and operate on the real AST — no regex substitutions.

## Installation

Add the gem to your project's `Gemfile` (it only needs to be available to the
language server, so the `:development` group is the right place):

```ruby
group :development do
  gem "ruby-lsp-refactor"
end
```

Then run:

```bash
bundle install
```

The add-on is discovered and activated automatically by ruby-lsp — no further
configuration is required.

## Supported refactorings

Place your cursor anywhere on the relevant construct and open the code-actions
menu (`Cmd+.` in VS Code / Zed, or your editor's equivalent).

### Conditionals

#### Convert to post-conditional

Collapses a single-statement `if` or `unless` block into a trailing modifier.

```ruby
# Before
if user.qualified?
  user.approve!
end

# After
user.approve! if user.qualified?
```

#### Convert to block if / Convert to block unless

The reverse — expands a trailing modifier back into a full block.

```ruby
# Before
user.approve! if user.qualified?

# After
if user.qualified?
  user.approve!
end
```

#### Convert to unless / Convert to if

Toggles between `if` and `unless` on a block conditional with no `else` branch.
When the predicate already starts with `!`, the negation is stripped
automatically.

```ruby
# Before
if !user.banned?
  user.login!
end

# After — negation stripped
unless user.banned?
  user.login!
end
```

#### Invert if/else

Negates the condition and swaps the two branches. Double-negation (`!!`) is
cancelled automatically.

```ruby
# Before
if user.admin?
  grant!
else
  deny!
end

# After
if !user.admin?
  deny!
else
  grant!
end
```

---

### Strings

#### Convert to interpolated string

Upgrades a single-quoted string to double-quotes so you can immediately add
`#{}` interpolation. Embedded `"` characters are escaped.

```ruby
'hello world'  →  "hello world"
```

#### Convert to string array / Convert to bracket array

Converts between a bracket array of plain strings and `%w[]` syntax.

```ruby
["foo", "bar", "baz"]  →  %w[foo bar baz]
%w[foo bar baz]        →  ["foo", "bar", "baz"]
```

#### Wrap in freeze / Remove freeze

Adds or removes `.freeze` on a string literal.

```ruby
"hello"          →  "hello".freeze
"hello".freeze   →  "hello"
```

---

### Collections

#### Convert to symbol array

Converts a bracket array of plain symbols into a `%i[]` word array.

```ruby
[:foo, :bar, :baz]  →  %i[foo bar baz]
```

#### Convert to keyword syntax

Converts hash-rocket pairs whose keys are plain symbols into modern keyword
syntax. Mixed hashes are handled gracefully — only eligible pairs are
converted.

```ruby
{ :name => "Alice", :age => 30 }  →  { name: "Alice", age: 30 }
```

#### Convert to .flat_map

Collapses a `map` + `flatten` / `flatten(1)` chain.

```ruby
items.map { |i| i.tags }.flatten(1)  →  items.flat_map { |i| i.tags }
```

#### Convert to .find

Collapses a `select` + `first` chain.

```ruby
users.select { |u| u.admin? }.first  →  users.find { |u| u.admin? }
```

#### Convert to .filter_map

Collapses a `map` + `compact` chain.

```ruby
items.map { |i| i.value }.compact  →  items.filter_map { |i| i.value }
```

---

### Variables & constants

#### Inline variable

Removes a local variable assignment and replaces every subsequent read with the
original right-hand-side expression.

```ruby
# Before — cursor on the assignment
result = user.calculate
puts result
log result

# After
puts user.calculate
log user.calculate
```

#### Extract local variable

Wraps any expression under the cursor in a new local variable inserted on the
line above.

```ruby
user.full_name.upcase
# After
variable = user.full_name.upcase
variable
```

#### Extract constant

Extracts a literal value (integer, float, string, symbol) inside a class or
module into a named constant at the top of the enclosing body.

```ruby
# Before — cursor on 100
class Processor
  def run
    items.first(100)
  end
end

# After
class Processor
  EXTRACTED_CONSTANT = 100

  def run
    items.first(EXTRACTED_CONSTANT)
  end
end
```

---

### Methods & classes

#### Extract to method

Extracts a local variable's right-hand-side into a new `private` method.
Variables defined before the extraction point that are referenced in the
expression are automatically forwarded as parameters.

```ruby
# Before — cursor on the assignment
def process(data)
  threshold = 10
  result = data.select { |x| x > threshold }
  result
end

# After
def process(data)
  threshold = 10
  result = result(threshold)
  result
end

  private

  def result(threshold)
    data.select { |x| x > threshold }
  end
```

#### Add parameter

Appends a `new_param` placeholder to a method's parameter list. Parentheses
are added automatically when the method has none.

```ruby
def greet(name)  →  def greet(name, new_param)
def greet        →  def greet(new_param)
```

#### Convert to keyword arguments

Rewrites required positional parameters to keyword arguments. Optional
parameters, rest args, and block parameters are left unchanged.

```ruby
def create(name, age)  →  def create(name:, age:)
```

#### Convert to attr_accessor

Detects an `attr_reader` paired with a canonical manual writer
(`def name=(val); @name = val; end`) and collapses them into a single
`attr_accessor`.

```ruby
# Before — cursor on either line
attr_reader :name
def name=(val)
  @name = val
end

# After
attr_accessor :name
```

#### Wrap body in rescue

Wraps a method's entire body in a `rescue StandardError => e` clause with a
`raise` placeholder so you can fill in the error handling without accidentally
swallowing exceptions.

```ruby
# Before
def call
  do_thing
end

# After
def call
  do_thing
rescue StandardError => e
  raise
end
```

#### Convert to explicit super

Converts a bare `super` (which forwards all arguments implicitly) into an
explicit `super(param1, param2, ...)` using the enclosing method's parameter
names.

```ruby
def initialize(name, age)
  super          →  super(name, age)
end
```

---

### Operators & blocks

#### Convert to do…end block / Convert to brace block

Toggles a block between `{ }` and `do…end` style. Multi-statement blocks are
always expanded to `do…end`; single-statement `do…end` blocks can be collapsed
to brace style.

```ruby
users.each { |u| u.activate! }
# After
users.each do |u|
  u.activate!
end
```

#### Convert `&&` to `and` / `and` to `&&`

Toggles between symbolic and word forms of the logical AND operator.

```ruby
user.valid? && user.save  →  user.valid? and user.save
```

#### Convert `||` to `or` / `or` to `||`

Toggles between symbolic and word forms of the logical OR operator.

```ruby
a || b  →  a or b
```

#### Simplify raise

Removes the redundant `RuntimeError` class from a two-argument `raise` or
`fail` call. `RuntimeError` is Ruby's default exception class and need not be
stated explicitly.

```ruby
raise RuntimeError, "oops"  →  raise "oops"
```

---

### RSpec

#### Extract to let

Moves a local variable assignment inside an `it`/`specify`/`example`/`scenario`
block into a `let` declaration above the example.

```ruby
# Before — cursor on the assignment
it "logs in" do
  user = User.new(name: "Alice")
  expect(user.name).to eq("Alice")
end

# After
let(:user) { User.new(name: "Alice") }

it "logs in" do
  expect(user.name).to eq("Alice")
end
```

#### Convert let to let! / let! to let

Toggles between lazy (`let`) and eager (`let!`) memoization.

```ruby
let(:user) { User.new }   →  let!(:user) { User.new }
let!(:user) { User.new }  →  let(:user) { User.new }
```

---

## Development

```bash
bin/setup             # install dependencies
bundle exec rake test # run the test suite
bundle exec rake      # lint + test
```

To try the add-on against a local project without publishing to RubyGems, add
a path reference to that project's `Gemfile`:

```ruby
gem "ruby-lsp-refactor", path: "/path/to/ruby-lsp-refactor"
```

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/tachyons/ruby-lsp-refactor.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
