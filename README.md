# Live Background Demo

To try various ways of doing long-running work in Phoenix LiveView, start with the boilerplate:

```bash
mix archive.install hex phx_new
mix phx.new --live --no-ecto --no-gettext live_bg_demo
cd live_bg_demo
mix deps.get
npm install --prefix assets
```

In order of the commit history in [`garthk/live_bg_demo`][repo], let's...

[repo]: https://github.com/garthk/live_bg_demo

## Do the work in `handle_event/3`

Before you launch the server, replace the main view in `lib/live_bg_demo_web/live/page_live.ex`:

```elixir
defmodule LiveBgDemoWeb.PageLive do
  use LiveBgDemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, counts: %{fast: 0, slow: 0})}
  end

  @impl true
  def handle_event("slow", %{}, socket) do
    :timer.sleep(5000)
    {:noreply, assign(socket, :counts, update_in(socket.assigns.counts, [:slow], &(&1 + 1)))}
  end

  def handle_event("fast", %{}, socket) do
    :timer.sleep(10)
    {:noreply, assign(socket, :counts, update_in(socket.assigns.counts, [:fast], &(&1 + 1)))}
  end
end
```

Also replace the `<form>` in `lib/live_bg_demo_web/live/page_live.html.leex`:

```html
  <form phx-submit="fast">
    <input type="number" id="count" size="3" value="<%= @counts.fast %>" disabled>
    <button type="submit" phx-disable-with="Working...">Count Fast</button>
  </form>

  <form phx-submit="slow">
    <input type="number" id="count" size="3" value="<%= @counts.slow %>" disabled>
    <button type="submit" phx-disable-with="Working...">Count Slow</button>
  </form>
```

Now launch your server and open `http://localhost:4000`:

```bash
iex -S mix phx.server
```

If you click the "Count Fast" button, you'll see the number above it change quickly. If you watch the top of the page, you'll see a blue stripe flash across it thanks to [`nprogress`][nprogress] hooked up to the `phx:page-loading-start` and `phx:page-loading-stop` events in `assets/js/app.js`. The "Count Fast" button also changes, but it's hard to catch.

If you click the "Count Slow" button, you can clearly catch the change: the button says "Working..." for five seconds while you wait for the number above it to change. The `View` class in the browser replaced the input's inner HTML with its `phx-disable-with` attribute while it waited for a reply; see LiveView's [JavaScript client specifics] for details.

So far, so good, but try clicking "Count Slow" and then, without waiting, click "Count Fast". This time, you can see "Count Fast" change to "Working...", because the view process is blocked. LiveView can't call the second clause of your [LiveView.handle_event/3] callback until the first finishes its call to [:timer.sleep/1] and returns.

## Do the work in `handle_info/2`

I've seen advice to instead have your view [send/2] itself a message and do slow work in your [LiveView.handle_info/2] callback instead, like this:

```elixir
  @impl true
  def handle_event("slow", %{}, socket) do
    send(self(), :slow)
    {:noreply, socket}
  end

  def handle_event("fast", %{}, socket) do
    :timer.sleep(10)
    {:noreply, assign(socket, :counts, update_in(socket.assigns.counts, [:fast], &(&1 + 1)))}
  end

  @impl true
  def handle_info(:slow, socket) do
    :timer.sleep(5000)
    {:noreply, assign(socket, :counts, update_in(socket.assigns.counts, [:slow], &(&1 + 1)))}
  end
```

Press "Count Slow". You can catch the `nprogress` strip, again, but that aside nothing happens for five seconds. If you press either button during that five seconds, though, you'll see that the view is just as blocked. LiveView can't call `handle_event/3` until `handle_info/2` returns.

[:timer.sleep/1]: http://erlang.org/doc/man/timer.html#sleep-1
[JavaScript client specifics]: https://hexdocs.pm/phoenix_live_view/form-bindings.html#javascript-client-specifics
[LiveView.handle_event/3]: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#c:handle_info/3
[LiveView.handle_info/2]: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#c:handle_info/2
[nprogress]: https://www.npmjs.com/package/nprogress

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
