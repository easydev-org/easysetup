{ pkgs }:
# clang from nixpkgs already brings lld and the llvm binutils it needs, and its
# closure includes the C++ headers - the three things the hand-written build had
# to discover one CI round at a time.
pkgs.clang
