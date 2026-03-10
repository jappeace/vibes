# Haskell vibes
Experimenting with claude to do various refactor
style jobs in Haskell.

For example we're depending on a package
we no longer want to depend on (say basement), 
rewrite the functions from basement
to functions within base and ghc-prim.

Seems to work alright.

## Container
I do not actually trust these llm's,
but I"m not going to babysit their every
action, so I run them in a container.


Claude doesn't get to see how we start the container.

### WARNING
I've seen it attempt to write into /etc/shadow 
to solve the home folder not being writable.

That's an attempt at privilege escalation!
