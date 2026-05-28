# Contributing

If you want to submit a pull request, please flatten unnecessarily nested `if/when/let` blocks using `if-let*/when-let*/and-let*`, remove single-use local variables, and avoid using cl-lib.

Also, feel free to raise the minimum supported version of the package if it would make the code of your PR any simpler! Elisp is complicated enough without supporting old versions.
