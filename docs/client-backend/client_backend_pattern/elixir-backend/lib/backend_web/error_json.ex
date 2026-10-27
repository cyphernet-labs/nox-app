defmodule BackendWeb.ErrorJSON do
  @moduledoc "Renders framework-level errors (404 route miss, 500) as JSON."

  def render(template, _assigns) do
    %{error: Phoenix.Controller.status_message_from_template(template)}
  end
end
