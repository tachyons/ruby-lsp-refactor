# ruby-lsp-refactor

A [ruby-lsp](https://github.com/Shopify/ruby-lsp) add-on that provides safe,
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

### Phase 1 — Local rewrites

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

Works with `unless` too:

```ruby
# Before
unless user.banned?
  user.login!
end

# After
user.login! unless user.banned?
```

#### Convert to block if / Convert to block unless

The reverse operation — expands a trailing modifier back into a full block.

```ruby
# Before
user.approve! if user.qualified?

# After
if user.qualified?
  user.approve!
end
```

#### Convert to unless / Convert to if

Toggles between `if` and `unless` on a block conditional that has no `else`
branch. When the predicate already starts with `!`, the negation is stripped
automatically to keep the result clean.

```ruby
# Before
if user.active?
  user.greet!
end

# After
unless user.active?
  user.greet!
end
```

```ruby
# Before — negated predicate
if !user.banned?
  user.login!
end

# After — negation stripped
unless user.banned?
  user.login!
end
```

#### Invert if/else

Negates the condition and swaps the two branches of an `if/else` block.
Double-negation (`!!`) is cancelled automatically.

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

#### Convert to interpolated string

Upgrades a single-quoted string literal to double-quotes so you can immediately
add `#{}` interpolation. Any `"` characters inside the string are escaped.

```ruby
# Before
'hello world'

# After
"hello world"
```

---

### Phase 2 — Variable & literal optimisation

#### Inline variable

Removes a local variable assignment and replaces every subsequent read of that
variable with the original right-hand-side expression.

```ruby
# Before — cursor on the assignment line
result = user.calculate
puts result
log result

# After
puts user.calculate
log user.calculate
```

#### Extract local variable

Wraps any expression under the cursor in a new local variable assignment
inserted on the line above.

```ruby
# Before — cursor on the expression
user.full_name.upcase

# After
variable = user.full_name.upcase
variable
```

#### Convert to keyword syntax

Converts hash-rocket pairs whose keys are plain symbols into modern keyword
syntax. Mixed hashes (string keys, computed keys) are handled gracefully —
only the eligible pairs are converted.

```ruby
# Before
{ :name => "Alice", :age => 30 }

# After
{ name: "Alice", age: 30 }
```

#### Convert to symbol array

Converts a bracket array of plain symbols into a `%i[]` word array.

```ruby
# Before
[:foo, :bar, :baz]

# After
%i[foo bar baz]
```

---

### Phase 3 — Advanced structure

#### Extract to method

Extracts a local variable's right-hand-side expression into a new `private`
method. Variables that are defined before the extraction point and referenced
inside the expression are automatically detected and forwarded as method
parameters.

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

Appends a `new_param` placeholder to a method's parameter list. If the method
has no parameters yet, parentheses are added automatically.

```ruby
# Before — cursor anywhere inside the def
def greet(name)
  puts name
end

# After
def greet(name, new_param)
  puts name
end
```

```ruby
# Before — no parameters
def greet
  puts "hello"
end

# After
def greet(new_param)
  puts "hello"
end
```

#### Convert to keyword arguments

Rewrites all required positional parameters in a method signature to keyword
arguments. Optional parameters, rest args, and block parameters are left
unchanged.

```ruby
# Before — cursor anywhere inside the def
def create(name, age)
  User.new(name, age)
end

# After
def create(name:, age:)
  User.new(name, age)
end
```

#### Extract to let _(RSpec)_

When the cursor is on a local variable assignment inside an RSpec `it`,
`specify`, `example`, or `scenario` block, this action moves the assignment
into a `let` declaration inserted above the example.

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

---

## Development

```bash
bin/setup        # install dependencies
bundle exec rake test   # run the test suite
bundle exec rake        # lint + test
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
