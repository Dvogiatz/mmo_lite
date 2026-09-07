defmodule MmoLite.FloorSupervisor do
  @moduledoc """
  Dynamically starts one `MmoLite.Floor` process per floor number, the
  first time a player enters it. Floors are `:temporary` — when a `Floor`
  stops itself after sitting empty (see `MmoLite.Floor`), it's simply gone;
  re-entering that floor number later starts a fresh one.
  """

  use DynamicSupervisor

  def start_link(opts),
    do: DynamicSupervisor.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Starts the floor process for `floor_num` if it isn't already running."
  def ensure_started(floor_num) do
    case Registry.lookup(MmoLite.FloorRegistry, floor_num) do
      [{pid, _}] ->
        pid

      [] ->
        case DynamicSupervisor.start_child(__MODULE__, {MmoLite.Floor, floor_num}) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end
    end
  end
end
