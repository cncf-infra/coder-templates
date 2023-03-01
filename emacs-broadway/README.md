---
name: Develop in Emacs on the Web!
description: Get started with Emacs development.
tags: [cloud, emacs]
---

# Getting started

Click on the Emacs-Broaway url within the workspace to access GUI Emacs via a browser.

Emacs is compiled to run with GDK_BACKEND=broadway on a BROADWAY_DISPLAY
It required a build of emacs with `./configure --with-pgtk --with-cairo --with-native-compilation --with-json --with-modules`

# Current Status

Based heavily on the work from @emacs-lsp : https://github.com/emacs-lsp/lsp-gitpod

<!-- Built over at: https://launchpad.net/~hippiehacker/+archive/ubuntu/emacs-broadway -->

Container source at : https://github.com/ii/emacs-coder/blob/master/Dockerfile
Includes ii's humacs.org doom config : https://github.com/humacs/.doom.d#humacs-doomd
