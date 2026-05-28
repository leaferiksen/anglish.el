# Anglish Flymake Backend

This is a Flymake backend to bid [Anglish-Friendly](https://anglisc.miraheze.org/wiki/How_To_Tell_If_a_Word_Is_Anglish-Friendly) alternatives to Latin, Greek, and French loanwords. Check out [r/anglish](https://www.reddit.com/r/anglish/) to learn more about the linguistics nerds who came up with this conlang.

Here is how I download it:

```elisp
(setopt use-package-vc-prefer-newest t)

(use-package anglish
  :ensure t
  :vc (:url "git@github.com:leaferiksen/anglish.el.git")
  :hook (markdown-ts-mode md-ts-mode))
```

I think this is a fun tool to explore what your own personal writing style would be in an alternate timeline’s version of English. `anglish.el` specifically corrects words which have Anglish alternatives that are still in modern english, since I am more interested in how this can change the tone of my English writing than learning the full conlang.
