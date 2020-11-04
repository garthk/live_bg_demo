# Live Background Demo

To try various ways of doing long-running work in Phoenix LiveView, start with the boilerplate:

```bash
mix archive.install hex phx_new
mix phx.new --live --no-ecto --no-gettext live_bg_demo
cd live_bg_demo
mix deps.get
npm install --prefix assets
```

## Usual instructions

To start your Phoenix server:

* Install dependencies with `mix deps.get`
* Install Node.js dependencies with `npm install --prefix assets`
* Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Learn more

* [Official website](https://www.phoenixframework.org/)
* [Guides](https://hexdocs.pm/phoenix/overview.html)
* [Docs](https://hexdocs.pm/phoenix)
* [Forum](https://elixirforum.com/c/phoenix-forum)
* [Source](https://github.com/phoenixframework/phoenix)
