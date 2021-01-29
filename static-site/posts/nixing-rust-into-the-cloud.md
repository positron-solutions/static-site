---
title: Nixing Rust Into the Cloud
published_date: "2021-01-21 06:53:07 +0000"
layout: default.liquid
is_draft: false
permalink: /posts/nixing-rust-into-the-cloud
data:
    synopsis: >-
        Nix and containers go together _extremely_ well. See how we develop,
        build, and deliver this website. Source for the entire site is
        [published here](https://github.com/positron-solutions/static-site),
        providing a coherent example to go along with this article. Special
        thanks to the [Cobalt](https://cobalt-org.github.io/getting-started/)
        maintainers and [Static Web
        Server](https://github.com/joseluisq/static-web-server) maintainers
---

<section class="blog meat">
<div class="inner">

# {{ page.title }}

{{ page.data.synopsis }}

## Foreword

This website is itself part of an ongoing bootstrap. Like any good bootstrap,
this article will be refined as both it and its self-description improve. Much
of the nix boilerplate is soon to be reduced as we finish implementing planned
features for [cargo2nix](https://github.com/cargo2nix/cargo2nix), so don't be
afraid of all the scary looking nix code in the source.

All of our articles on tooling are written for the audience of an engineering
lead whose job it is to achieve smooth, rapid adoption with their technology
inventory

## Bootstrapping Projects With Nix & Rust

When moving over to nix, while CI and building containers is cool, one of the
chief advantages is being able to reproduce dev environments in a conflict-free
way across machines.  Before we can use a dev shell that has all the tools, we
need some tooling that can get us the rest of the tools.  It's a chicken-and-egg
bootstrap problem. **Avoid a complex bootstrap DAG by providing a fairly
complete set of tools independently of your project shell**. The cost of this
bootstrap is that, in the beginning, versions are not quite normalized. This is
okay until a proper dev shell is ready with exactly one coherent set of
versions. In our projects, we like to start with global versions of at least:

- Rust Platform
- niv (or just nix if using flakes)
- cargo2nix

Once the shell is able to bootstrap and provide its own tools, the cargo2nix
version (and the format of the Cargo.nix it generates) can be normalized and
become self-hosting.

#### Sometimes shells get broken You absolutely need bootstrap versions for faster recovery when a user inevitably trashes their local dev shell.

"Global" versions can refer to those managed in some broader scope of system
administration. We use
[home-manager](https://github.com/nix-community/home-manager) in combination
with some [NixOS modules](https://nixos.wiki/wiki/Module) or [Nix
Darwin](https://github.com/LnL7/nix-darwin) where appropriate. Packages provided
here are "global" compared to the project-specific dev shell. **The modular
nature of these tools allows dev environments to be set up in chunks as
needed**, leading to less groaning about having to build Spark just to run a
bash script

### Allow some flex at the platform level

Particularly where the operating system is involved, such as how you run
containers on your machine, it is better to allow versions running on the metal
to float and prefer to rely on the API version of the abstraction they
expose. For local kubernetes, this means paying attention to the kubernetes API
in use and not the flavor of minikube vs Docker Desktop etc. Some version of
these tools might work like a charm on one platform. When talking to different
operating systems, there's no such thing as running the same version everywhere,
so it's best to stick with what's smooth per operating system.

### Pin Lazily

While pinning is great for reproducibility, your "global" packages should also
be well-maintained, enough so that most of your projects just get naturally
updated. Eager pinning, while well-intended, tends to result in a much larger
maintenance overhead and hides upcoming upgrade pains until the package has aged
so much that it's no longer easy and also not clear where to start. With lazy
pinning, you pin only when it gets you back to a running state faster so you can
walk the versions only where it's actually needed. If your repository has been
nixifying fine with vanilla cargo2nix, don't eagerly pin cargo2nix as a per-repo
tool

## Tools & Roles

- Direnv has excellent editor integration and nix integration. The result is
  that editors like [emacs](https://github.com/hlissner/doom-emacs) magically
  pick up the correct versions of tools when invoking their own integrations
- Nix is our dependency management system. Don't be fooled by the fact that you
  embed a lot of build commands in to derivations. Nix is mainly about
  dependency
- Niv (or nix flakes) manages our pins and provides a decent UI for creating and
  maintaining pins
- Carog2nix adds native dependency predictability to Rust projects. Through
  natural integration with `mkShell` for direnv, it's possible to inject
  dependencies per project into the shell, preventing version collisions while
  giving the user the familiar `cargo run` and `cargo build` workflows
- Helm charts are mainly used to provide some atomicity for configuration
  changes, using templating to avoid scattered duplication that is frequent when
  deployment configurations are being developed
- Skaffold is used to gain faster debugging of these charts. A development cloud
  environment (dev cluster) is another option, but due to cost, complexity, and
  not sharing space together, may be suboptimal. We just want to run the program
  as a perhaps incompletely configured container at this phase
- Github Actions is used in the CI role, gaiting PR merges and building &
  uploading slugs on deployment triggers (merge to master or tag creation
  etc). The gitops pattern here relies partly on CI actions to create the images
  that CD will then pick up in pull fashion
- ArgoCD plays a critical role of converging the state of what we want, as
  defined in git, with the current running state. Asking Github actions to do
  this in a push manner would be very unpleasant. ArgoCD convergence in pull
  makes gitops work
  
## The Payload

We will use Cobalt to build a static site. Only trouble is, The [Cobalt quick
start guide](https://cobalt-org.github.io/getting-started/) suggests we run
`cobalt init` but we don't yet have cobalt available. We might want to use the
publish commands later in CI, so let's just build it with Nix. We will check out
cobalt as a submodule, nixify it with cargo2nix, and then install the result
into a shell that will have cobalt avaialable

```shell
$ cobalt init static-site
$ cd static-site
$ cobalt serve

[info] Server Listening on http://localhost:3000
```

Okay great. We can create a nix derivation to perform the `cobalt build` on our
checked in site source to have it available for a slug.

Next, we want static-web-server. Again, the source is checked out as a submodule
for nixifying but pinned for import as a regular `fetchGit` dependency. Once
that's done, we can also serve our built static site like so, again, before
moving to kubernetes, we can see what hosting the site looks like:

```shell
$ cobalt build
$ static-web-server --root _site \
  --assets _site/public/ \
  --port 3001 \
  --page404 _site/404.html \
  --page50x _site/500.html 

2021-01-28T21:33:24 [SERVER] - Static HTTP Server "my-static-server" is listening on [::]:3000
```

Now we can build the site source into a completed `_site` directory and serve it
with out intended web server. Ready to containerize and ship!

## The Payoff

Some nix sleuthing quickly finds out the dependencies for the server in the slug:

```shell
nix-build -A siteServerContainer

# follow the drv files using nix path-info and nix show-derivation

nix path-info -shr /nix/store/4jg7z2fnfn3l0i7y7d7d83xmzzwy2r4v-crate-static-web-server-1.12.0-bin
/nix/store/0bdb81p95mip0z30582lcyz76pv2zm41-openssl-1.1.1i-bin                	 757.8K
/nix/store/1pjg5gp2vhpyks4vwvirx5g9qdnrprav-openssl-1.1.1i                    	   4.0M
/nix/store/33idnvrkvfgd5lsx2pwgwwi955adl6sk-glibc-2.31                        	  29.7M
/nix/store/4jg7z2fnfn3l0i7y7d7d83xmzzwy2r4v-crate-static-web-server-1.12.0-bin	   2.1M
/nix/store/czc3c1apx55s37qx4vadqhn3fhikchxi-libunistring-0.9.10               	   1.6M
/nix/store/m34wj7jjn76h3kfwa23in0a81qdmfk27-openssl                           	  33.4K
/nix/store/xim9l8hym4iga6d4azam4m0k0p1nw2rm-libidn2-2.3.0                     	 217.5K
/nix/store/zw9qzyal16dk0sy5rshlrh2889z88ijs-openssl-1.1.1i-dev                	   1.3M
```

Glibc looks big. Normally switching to musl would mean a lot of headache to
obtain all the dependencies from source to start the whole entire build.  With
nix, we just set one extra variable on our build command:

```shell
nix-build -A siteServerContainer --arg crossSystem '{ config = "x86_64-unknown-linux-musl"; }'
```

## What's Next?

For this website, the Rust package being shipped was basically
[static-web-server](https://github.com/joseluisq/static-web-server), meaning we
packaged a Rust application but didn't talk much about Rust development. The
next article will publish a minimal Rust applicaiton with more focus on the
libraries and tools you expect to be available when writing a containerized
program. Also, we totally gloss over the platform differences. Another article
will discuss supporting OSX & Linux stacks in a similar way to get your
engineers mostly on the same page fast.
