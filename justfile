# Task entry points named the way the other Hegel implementations name theirs,
# so that `just check` means the same thing here as it does in hegel-rust,
# hegel-go, hegel-typescript, hegel-java, hegel-ocaml, and hegel-cpp.
#
# Rake holds every real task definition. Each recipe below delegates in a
# single line and adds nothing of its own, so the two entry points cannot
# drift apart. Contributors who do not have `just` lose nothing: run the Rake
# task in the recipe instead.

default: check

# run the tests and the linter, the same as CI
check:
    bundle exec rake

# run the tests
test:
    bundle exec rake test

# run the tests with coverage measurement enforced at 100%
coverage:
    bundle exec rake coverage

# run the linter
lint:
    bundle exec rake standard

# apply the fixes the linter considers safe
format:
    bundle exec rake standard:fix

# install the dependencies
setup:
    bin/setup
