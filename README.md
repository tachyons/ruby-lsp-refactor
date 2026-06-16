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

#### Convert to early return

Converts a guard `if` block at the top of a method into a `return unless`
statement, eliminating unnecessary nesting. The method body must have no
`else` branch and the `if` must be the first statement.

```ruby
# Before — cursor on the if
def charge_purchase(order)
  if order.fulfilled?
    OrderChargeConfirmation.new(order).create!
  end
end

# After
def charge_purchase(order)
  return unless order.fulfilled?
  OrderChargeConfirmation.new(order).create!
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

#### Extract predicate methods

Extracts each operand of a compound `&&` or `||` expression that is the sole
statement in a method into its own private predicate method. The generated
names `predicate_1?` / `predicate_2?` are placeholders — rename them to
reflect intent.

```ruby
# Before — cursor on the compound expression
def eligible_for_return?
  expired_orders.exclude?(self) && self.value > MINIMUM_RETURN_VALUE
end

# After
def eligible_for_return?
  predicate_1? && predicate_2?
end

private

def predicate_1?
  expired_orders.exclude?(self)
end

def predicate_2?
  self.value > MINIMUM_RETURN_VALUE
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

#### Convert to tap

Converts a sequence of method calls on the same receiver followed by a bare
return of that receiver into an `Object#tap` block, grouping the operations
and removing the explicit return.

```ruby
# Before — cursor anywhere in the method
def do_something
  obj.do_first_thing
  obj.do_second_thing
  obj.do_third_thing
  obj
end

# After
def do_something
  obj.tap do |o|
    o.do_first_thing
    o.do_second_thing
    o.do_third_thing
  end
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

## Planned refactorings

The items below are on the roadmap but not yet implemented. They are tracked
here so the intent is not lost.

### Single-file (not yet implemented)

| Refactoring | Description |
|---|---|
| **Introduce field** | Extracts an expression inside a method into an instance variable (`@name`), inserting the assignment at the top of the method or into `initialize`. |

### Multi-file

These refactorings create new files and/or update call sites across the
project. The ones marked ✅ are already implemented using `document_changes`
in the `WorkspaceEdit` response, which lets a single code action atomically
create files and edit multiple documents. The ones marked 🔲 require
workspace-level index support or are pending implementation.

#### ✅ Extract Include File

Extracts a top-level `module` or `class` into its own file and replaces it
with a `require_relative` statement. Offered when the cursor is on a module or
class that coexists with other top-level statements in the same file.

```ruby
# Before — app/models/user.rb (cursor on the module)
module Greetable
  def greet = "hello"
end

class User
  include Greetable
end

# After — app/models/greetable.rb (new file, created automatically)
# frozen_string_literal: true

module Greetable
  def greet = "hello"
end

# After — app/models/user.rb (modified)
require_relative "greetable"

class User
  include Greetable
end
```

#### 🔲 Extract Service Object

Moves callback logic out of a controller into a dedicated service object file.
Addresses the Rails antipattern of using `after_action` callbacks for
operations that depend on the success of the triggering action.

```ruby
# Before — app/controllers/users_controller.rb
class UsersController < ApplicationController
  after_action :send_confirmation_email, only: [:create]

  def create
    @user = User.create!(user_params)
  end
end

# After — app/services/user_confirmation_service.rb (new file)
class UserConfirmationService
  def initialize(user) = @user = user

  def call
    AccountCreationMailer.new(@user).deliver! if @user.persisted?
  end
end

# After — app/controllers/users_controller.rb (modified)
class UsersController < ApplicationController
  def create
    @user = User.create!(user_params)
    UserConfirmationService.new(@user).call
  end
end
```

#### 🔲 Extract Form Object

Extracts a model that uses `accepts_nested_attributes_for` into a plain Ruby
form object that includes `ActiveModel::Model`, making the form flat,
explicitly validated, and easy to test.

Creates a new file under `app/forms/` and updates the controller and view to
use the form object instead of the model directly.

#### 🔲 Extract Policy Class

When a method contains more than two or three compound conditions, extracts
them all into a dedicated policy class with individual predicate methods. Each
predicate becomes a public method on the policy, making them independently
testable without stubs.

```ruby
# Before — single method with many conditions
def eligible_for_return?
  not_expired? && over_minimum_value? && customer_not_fraudulent?
end

# After — app/policies/return_eligibility_policy.rb (new file)
class ReturnEligibilityPolicy
  def initialize(order) = @order = order

  def eligible?
    not_expired? && over_minimum_value? && customer_not_fraudulent?
  end

  def not_expired?             = Order.expired_orders.exclude?(@order)
  def over_minimum_value?      = @order.value > Order::MINIMUM_RETURN_VALUE
  def customer_not_fraudulent? = @order.user.not_fraudulent?
end

# After — calling code (modified)
def eligible_for_return?
  ReturnEligibilityPolicy.new(self).eligible?
end
```

#### 🔲 Combine Functions into Class

When several methods in a file all take the same object as their first
argument, extracts them into a new class where that object becomes an injected
dependency. Implements the
[Combine Functions into Class](https://refactoring.com/catalog/combineFunctionsIntoClass.html)
pattern.

```ruby
# Before — repeated argument is a smell
def format_name(user) = "#{user.first_name} #{user.last_name}"
def greeting(user)    = "Hello, #{format_name(user)}"
def farewell(user)    = "Goodbye, #{format_name(user)}"

# After — app/presenters/user_presenter.rb (new file)
class UserPresenter
  def initialize(user) = @user = user

  def format_name = "#{@user.first_name} #{@user.last_name}"
  def greeting    = "Hello, #{format_name}"
  def farewell    = "Goodbye, #{format_name}"
end
```

#### 🔲 Introduce Null Object

When a method guards against a nil association with an `if` check before
delegating to it, extracts a null object class that implements the same
interface with safe default behaviour, removing the conditional entirely.

```ruby
# Before
if @user.has_address?
  @user.address.street_name
else
  "Unknown street"
end

# After — app/models/null_address.rb (new file)
class NullAddress
  def street_name = "Unknown street"
end

# After — app/models/user.rb (modified)
class User
  def address = @address || NullAddress.new
end

# After — calling code (no conditional needed)
@user.address.street_name
```

#### 🔲 Rename

Renames a method, class, module, constant, or local variable and updates
every reference to it across the entire project. Requires the ruby-lsp index
to locate all usages safely.

#### 🔲 Extract Parameter

Extracts an expression inside a method body into a new parameter, adding it
to the method signature and updating every call site in the project to pass
the extracted value.

```ruby
# Before
def greet
  "Hello, #{DEFAULT_NAME}"
end

# After — signature and all call sites updated
def greet(name = DEFAULT_NAME)
  "Hello, #{name}"
end
```

#### 🔲 Extract Superclass

Extracts selected methods from a class into a new superclass and makes the
original class inherit from it. Creates a new file for the superclass.

```ruby
# Before — app/models/animal.rb
class Animal
  def breathe = "breathing"
  def eat      = "eating"
  def speak    = raise NotImplementedError
end

# After — app/models/living_thing.rb (new file)
class LivingThing
  def breathe = "breathing"
  def eat      = "eating"
end

# After — app/models/animal.rb (modified)
class Animal < LivingThing
  def speak = raise NotImplementedError
end
```

#### 🔲 Extract Module

Extracts selected methods from a class into a new module and adds an
`include` statement. Creates a new file for the module.

```ruby
# Before
class Report
  def format_header = "=== Report ==="
  def format_footer = "=== End ==="
  def generate      = "#{format_header}\n...\n#{format_footer}"
end

# After — app/concerns/formattable.rb (new file)
module Formattable
  def format_header = "=== Report ==="
  def format_footer = "=== End ==="
end

# After — app/models/report.rb (modified)
class Report
  include Formattable
  def generate = "#{format_header}\n...\n#{format_footer}"
end
```

#### 🔲 Pull Members Up / Push Members Down

Moves methods between a class and its superclass. "Pull up" moves a method
from a subclass to the superclass; "push down" moves it from the superclass
into one or more subclasses. Both operations update all affected files.

#### 🔲 Safe Delete

Deletes a method, class, or constant only after verifying it has no usages
anywhere in the project. Requires the ruby-lsp index to confirm the symbol is
unreferenced before removing it.

#### 🔲 Extract Partial _(Rails)_

Extracts a fragment of an ERB view template into a new partial file and
replaces the original fragment with a `render` call.

```erb
<%# Before — app/views/users/show.html.erb %>
<div class="profile">
  <h1><%= @user.name %></h1>
  <p><%= @user.bio %></p>
</div>

<%# After — app/views/users/_profile.html.erb (new file) %>
<div class="profile">
  <h1><%= user.name %></h1>
  <p><%= user.bio %></p>
</div>

<%# After — app/views/users/show.html.erb (modified) %>
<%= render "profile", user: @user %>
```

#### 🔲 Extract Include File (generic)

Extracts an arbitrary block of Ruby code (not necessarily a named module or
class) into a new file and replaces it with a `require_relative` statement.
The ✅ variant above handles the named module/class case automatically; this
generic form would handle any selected lines.

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
