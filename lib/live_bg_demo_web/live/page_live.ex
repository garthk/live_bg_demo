defmodule LiveBgDemoWeb.PageLive do
  use LiveBgDemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, counts: %{fast: 0, slow: 0})}
  end

  @impl true
  def handle_event("slow", %{}, socket) do
    Task.async(fn -> delay(:slow, 5000) end)
    {:noreply, socket}
  end

  def handle_event("fast", %{}, socket) do
    Task.async(__MODULE__, :delay, [:fast, 10])
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
end
