# Positron's Static Site Source

[Positron's][positron] statically generated website is hosted with the source in
this repository. You can read more about this website on the [website
itself][blog]. Some of the tools used:

* CI & CD with [Github Actions][1] & [Argo CD][2]
* Builds slugs using [Nix][3]
* Local deploys with [Skaffold][4]
* Per-project Rust tooling with Nix shell
* Direnv integration with IDE's

## Requirements

Install Nix. So far only verified to run on Linux so far. No reason it should be
difficult on OSX.

## Getting Started

```shell
# allow or enter the shell to have tooling available
nix-shell

# host the site using cobalt for live rebuilds
cd static-site
cobalt serve
[info] Server Listening on http://localhost:3000

# host the website using the static-web-server binary
cobalt build
static-web-server --root _site \
  --assets _site/public/ \
  --port 3000 \
  --page404 _site/404.html \
  --page50x _site/500.html 

2021-01-28T21:33:24 [SERVER] - Static HTTP Server "my-static-server" is listening on [::]:3000

# host the site as a container served on local kubernetes
skaffold dev --port-forward
```

[actions]: https://github.com/features/actions
[argocd]: https://argoproj.github.io/argo-cd/
[blog]: https://positron.solutions/posts/nixing-rust-into-the-cloud
[nixos]: https://nixos.org/
[positron]: https://positron.solutions
[skaffold]: https://skaffold.dev/
