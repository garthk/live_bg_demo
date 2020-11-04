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

## Spawn processes with `Task.async/1`

To avoid being blocked, we need to spawn another process to do the heavy work. [Task.async/1] seems an obvious way to launch it, but if we call [Task.await/2] from our `LiveView` or `GenServer` callbacks we'll block our process for as long as the `timeout`. We can copy its techniques, though, and the documentation for [Task.async/3] gives us a clue. The last paragraph describes the key difference between a `Task` and any other process you might have spawned to call a function:

> The reply sent by the task will be in the format `{ref, result}`, where `ref` is the monitor reference held by the task struct and `result` is the return value of the task function.

When the function returns, the task's process sends its owner the result. For more clues, we can read the [Getting Started: Processes][processes] guide and the code of `await/2` in Elixir 1.11.1:

```elixir
  @spec await(t, timeout) :: term
  def await(%Task{ref: ref, owner: owner} = task, timeout \\ 5000) when is_timeout(timeout) do
    if owner != self() do
      raise ArgumentError, invalid_owner_error(task)
    end

    receive do
      {^ref, reply} ->
        Process.demonitor(ref, [:flush])
        reply

      {:DOWN, ^ref, _, proc, reason} ->
        exit({reason(reason, proc), {__MODULE__, :await, [task, timeout]}})
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        exit({:timeout, {__MODULE__, :await, [task, timeout]}})
    end
  end
```

The owning process passes the ownership check, then calls [receive/1]. The first match `{^ref, reply}` pins the task's monitor reference and binds its reply. If it receives a matching message before it times out, it calls [Process.demonitor/2] to drop the monitor and clean up any of its `:DOWN` messages.

Later on, we'll care about the `:DOWN` message and timeout, but for now let's see if we can solve our blocking problem. LiveView calls `receive/2` for us, but we can get the message as the first argument of our `handle_info/2`. All together, our procedure is to:

* Call `Task.async/1` or `Task.async/3` from our buttons' `handle_event/3` clauses
* Get its reply in our `handle_info/2`
* Call `Process.demonitor(ref, [:flush])` so we don't have to add a clause for the `:DOWN` message
* Update the socket's assigns

```elixir
  @impl true
  def handle_event("slow", %{}, socket) do
    Task.async(__MODULE__, :delay, [:slow, 5000])
    {:noreply, socket}
  end

  def handle_event("fast", %{}, socket) do
    Task.async(fn -> delay(:false, 10) end)
    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, key}, socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, :counts, update_in(socket.assigns.counts, [key], &(&1 + 1)))}
  end

  @doc false
  def delay(term, ms) do
    :timer.sleep(ms)
    term
  end
```

You can mash the "Count Slow" button five times, then the "Count Fast" button twenty times, and see the fast counter increment every time right after you hit the button. Eventually, the slow counter catches up as its tasks finish. The view is never blocked. Success!

For anything more complicated than a reliable timer with a predictable duration, of course, it can't be this easy. For now, though, we can mash the buttons a few more times to celebrate.

## Fail!

Failure is possible in most of the functions we're interested in calling while the user waits. We'd better find out what happens. First, let's make it obvious using the `phx-error` class documented in [Loading state and errors]. Add this to your `assets/css/app.scss`:

```css
.phx-error *{
  background-color: pink;
}
```

Add a button to trigger failure to your view template:

```html
  <form phx-submit="fail">
    <button type="submit" phx-disable-with="Working...">Fail</button>
  </form>
```

That'll fail without any extra code, now I think of it. Push it!

```plain
** (FunctionClauseError) no function clause matching in LiveBgDemoWeb.PageLive.handle_event/3
Last message: %Phoenix.Socket.Message{event: "event", payload: %{"event" => "fail", ...}, ...}
```

When our view crashes, its parent container gets a new `phx-error` class, turning everything inside it pink. LiveView dispatches the JavaScript event `phx:page-loading-start` on the window, kicking off [nprogress] in our default `assets/js/app.js`: you can see the blue stripe creep forward. Eventually LiveView calls our `mount/3` and (hidden) `render/1` in a new process. Some tidying up later, and we're back to normal.

Does it act the same when we add a matching clause but raise an exception in it?

```elixir
  def handle_event("fail", _, _) do
    raise "fail"
  end
```

Yes:

```plain
** (RuntimeError) fail
Last message: %Phoenix.Socket.Message{event: "event", payload: %{"event" => "fail", ...}, ...}
```

How about if we do so in a task? Replace that clause with:

```elixir
  def handle_event("fail", %{}, socket) do
    Task.async(__MODULE__, :delay_fail, ["fail", 10])
    {:noreply, socket}
  end

  @doc false
  def delay_fail(msg, ms) do
    :timer.sleep(ms)
    raise msg
  end
```

Push the button again...

```plain
[error] Task #PID<0.1313.0> started from #PID<0.1311.0> terminating
** (RuntimeError) fail
Function: &LiveBgDemoWeb.PageLive.delay_fail/2
```

Because we used `Task.async`, the task's process is linked to its owner: our view. When the task crashes, its owner crashes. The view starts again from scratch, and we're back to our starting state.

[:timer.sleep/1]: http://erlang.org/doc/man/timer.html#sleep-1
[JavaScript client specifics]: https://hexdocs.pm/phoenix_live_view/0.14.8/form-bindings.html#javascript-client-specifics
[LiveView.handle_event/3]: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#c:handle_info/3
[LiveView.handle_event/3]: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#c:handle_info/3
[LiveView.handle_info/2]: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#c:handle_info/2
[LiveView.handle_info/2]: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#c:handle_info/2
[Loading state and errors]: https://hexdocs.pm/phoenix_live_view/0.14.8/js-interop.html#loading-state-and-errors
[Process.demonitor/2]: https://hexdocs.pm/elixir/Process.html#demonitor/2
[Process.monitor/1]: https://hexdocs.pm/elixir/Process.html#monitor/1
[Task.async/1]: https://hexdocs.pm/elixir/Task.html#async/1
[Task.async/3]: https://hexdocs.pm/elixir/Task.html#async/3
[Task.await/2]: https://hexdocs.pm/elixir/Task.html#await/2
[nprogress]: https://www.npmjs.com/package/nprogress
[processes]: https://elixir-lang.org/getting-started/processes.html
[receive/1]: https://hexdocs.pm/elixir/Kernel.html#receive/1
[send/2]: https://hexdocs.pm/elixir/Kernel.html#send/2

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
