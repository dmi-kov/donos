defmodule Donos.Bot.Logic do
  use GenServer

  alias Donos.{Store, Session}
  alias Nadia.Model.{Update, Message}
  alias Nadia.Model.{Audio, Document, Sticker, Video, Voice, Contact, Location}

  import Donos.Bot.Util

  def start_link(_) do
    GenServer.start_link(__MODULE__, :none, name: __MODULE__)
  end

  def handle(update) do
    GenServer.cast(__MODULE__, {:handle, update})
  end

  @impl GenServer
  def init(:none) do
    {:ok, :none}
  end

  @impl GenServer
  def handle_cast({:handle, %Update{message: %Message{} = message}}, :none) do
    handle_message(message)
    {:noreply, :none}
  end

  @impl GenServer
  def handle_cast({:handle, %Update{edited_message: %{} = message}}, :none) do
    handle_edited_message(message)
    {:noreply, :none}
  end

  @impl GenServer
  def handle_cast({:handle, update}, :none) do
    IO.inspect({:unkown_update, update})
    {:noreply, :none}
  end

  @impl GenServer
  def handle_info({:ssl_closed, _}, offset) do
    {:noreply, offset}
  end

  defp handle_message(%{text: "/start"} = message) do
    Store.User.put(message.from.id)
    Session.get(message.from.id)

    response = "Привет анон, это анонимный чат"
    send_message(message.from.id, {:system, response})
  end

  defp handle_message(%{text: "/ping"} = message) do
    send_message(message.from.id, {:system, "pong"})
  end

  defp handle_message(%{text: "/relogin"} = message) do
    Session.stop(message.from.id)
    Session.start(message.from.id)
  end

  defp handle_message(%{text: "/setname"} = message) do
    response = "Синтаксис: /setname new-name"
    send_message(message.from.id, {:system, response})
  end

  defp handle_message(%{text: <<"/setname ", name::binary>>} = message) do
    response =
      case Session.set_name(message.from.id, name) do
        {:ok, name} -> "Твоё новое имя: #{name}"
        {:error, reason} -> "Ошибка: #{reason}"
      end

    send_message(message.from.id, {:system, response})
  end

  defp handle_message(%{text: "/getsession"} = message) do
    lifetime = Session.get_lifetime(message.from.id)
    response = "Длина твоей сессии в минутах: #{Duration.to(:minutes, lifetime)}"
    send_message(message.from.id, {:system, response})
  end

  defp handle_message(%{text: "/setsession"} = message) do
    response = "Нужно дописать длину сессии (в минутах) после /setsession"
    send_message(message.from.id, {:system, response})
  end

  defp handle_message(%{text: <<"/setsession ", lifetime::binary>>} = message) do
    response =
      try do
        lifetime = lifetime |> String.trim() |> String.to_integer()
        lifetime = Duration.from(:minutes, lifetime)

        case Session.set_lifetime(message.from.id, lifetime) do
          :ok ->
            "Твоя новая длина сессии (в минутах): #{Duration.to(:minutes, lifetime)}"

          {:error, reason} ->
            "Ошибка: #{reason}"
        end
      rescue
        ArgumentError -> "Ошибка: невалидный аргумент"
      end

    send_message(message.from.id, {:system, response})
  end

  defp handle_message(%{text: "/whoami"} = message) do
    name = Session.get_name(message.from.id)
    response = "Твое имя: #{name}"
    send_message(message.from.id, {:system, response})
  end

  defp handle_message(%{text: <<"/", command::binary>>} = message) do
    response = "Команда не поддерживается: #{command}"
    send_message(message.from.id, {:system, response})
  end

  defp handle_message(%{text: text} = message) when is_binary(text) do
    broadcast_content(message, fn user_id, name ->
      send_message(user_id, {:post, name, text}, reply_to: get_message_for_reply(message, user_id))
    end)
  end

  defp handle_message(%{audio: %Audio{file_id: file_id}} = message) do
    broadcast_content(message, fn user_id, name ->
      send_message(user_id, {:announce, name, "аудио"})

      Nadia.send_audio(user_id, file_id,
        caption: message.caption,
        reply_to: get_message_for_reply(message, user_id)
      )
    end)
  end

  defp handle_message(%{document: %Document{file_id: file_id}} = message) do
    broadcast_content(message, fn user_id, name ->
      send_message(user_id, {:announce, name, "файл"})

      Nadia.send_document(user_id, file_id,
        caption: message.caption,
        reply_to: get_message_for_reply(message, user_id)
      )
    end)
  end

  defp handle_message(%{photo: [_ | _] = photos} = message) do
    file_id = Enum.at(photos, -1).file_id

    broadcast_content(message, fn user_id, name ->
      send_message(user_id, {:announce, name, "пикчу"})

      Nadia.send_photo(user_id, file_id,
        caption: message.caption,
        reply_to: get_message_for_reply(message, user_id)
      )
    end)
  end

  defp handle_message(%{sticker: %Sticker{file_id: file_id}} = message) do
    broadcast_content(message, fn user_id, name ->
      send_message(user_id, {:announce, name, "стикер"})
      Nadia.send_sticker(user_id, file_id, reply_to: get_message_for_reply(message, user_id))
    end)
  end

  defp handle_message(%{video: %Video{file_id: file_id}} = message) do
    broadcast_content(message, fn user_id, name ->
      send_message(user_id, {:announce, name, "видео"})

      Nadia.send_video(user_id, file_id,
        caption: message.caption,
        reply_to: get_message_for_reply(message, user_id)
      )
    end)
  end

  defp handle_message(%{voice: %Voice{file_id: file_id}} = message) do
    broadcast_content(message, fn user_id, name ->
      send_message(user_id, {:announce, name, "голосовое сообщение"})

      Nadia.send_voice(user_id, file_id,
        caption: message.caption,
        reply_to: get_message_for_reply(message, user_id)
      )
    end)
  end

  defp handle_message(%{contact: %Contact{} = contact} = message) do
    broadcast_content(message, fn user_id, name ->
      send_message(user_id, {:announce, name, "контакт"})

      Nadia.send_contact(user_id, contact.phone_number, contact.first_name,
        last_name: contact.last_name,
        caption: message.caption,
        reply_to: get_message_for_reply(message, user_id)
      )
    end)
  end

  defp handle_message(%{location: %Location{latitude: latitude, longitude: longitude}} = message) do
    broadcast_content(message, fn user_id, name ->
      send_message(user_id, {:announce, name, "местоположение"})

      Nadia.send_location(user_id, latitude, longitude,
        caption: message.caption,
        reply_to: get_message_for_reply(message, user_id)
      )
    end)
  end

  defp handle_message(message) do
    IO.inspect({:unkown_message, message})
  end

  defp handle_edited_message(%{text: text} = message) when is_binary(text) do
    with {:ok, %Store.Message{} = stored_message} <- Store.Message.get(message.message_id) do
      text = format_message({:edit, stored_message.user_name, text})

      for {user_id, related_message_id} <- stored_message.related do
        Nadia.edit_message_text(user_id, related_message_id, "", text, parse_mode: "markdown")
      end
    else
      :error ->
        response = "Это сообщение уже нельзя редактировать"
        send_message(message.from.id, {:system, response})
    end
  end

  defp handle_edited_message(message) do
    IO.inspect({:unkown_edited_message, message})
  end
end
