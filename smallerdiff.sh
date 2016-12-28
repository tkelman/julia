#!/bin/sh
git remote add Sacha0 https://github.com/Sacha0/julia
git checkout master
git branch -D tk/sparsevechof
set -e # stop on failure
git fetch Sacha0
git checkout Sacha0/sparsevechof
git checkout -b tk/sparsevechof
cd base/sparse
head -n 1400 sparsematrix.jl > sparsematrix-head.jl
tail -n 2164 sparsematrix.jl > sparsematrix-tail.jl
cat sparsematrix-head.jl higherorderfns.jl sparsematrix-tail.jl > sparsematrix.jl
rm sparsematrix-head.jl sparsematrix-tail.jl
cd ../../test/sparse
head -n 1172 sparse.jl > sparse-head.jl
tail -n 528 sparse.jl > sparse-tail.jl
head -n 180 higherorderfns.jl > higherorderfns-head.jl
tail -n 74 higherorderfns.jl > higherorderfns-tail.jl
cat sparse-head.jl higherorderfns-tail.jl sparse-tail.jl higherorderfns-head.jl > sparse.jl
rm sparse-head.jl sparse-tail.jl higherorderfns-head.jl higherorderfns-tail.jl
cd ../..
