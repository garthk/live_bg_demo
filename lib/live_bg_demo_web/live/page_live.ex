defmodule LiveBgDemoWeb.PageLive do
  use LiveBgDemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, counts: %{fast: 0, slow: 0})}
  end

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
end
