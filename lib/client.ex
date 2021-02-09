defmodule Client do
    use GenServer
    require Logger

#------------------Registration------------------------
def perform_registration(server, username \\ "user123") do
    data = %{"function"=> "register", "username"=> username}
    #Logger.debug "data: #{inspect(data)}"
    send_message(server, data)
end

def send_message(receiver, data) do
    encoded_response = Poison.encode!(data)
    :gen_tcp.send(receiver, encoded_response)
end

def handle_cast({:register, data}, map) do
    if data["status"] != "success" do
        Logger.info "No success while registering"
    end
    {:noreply, map}
end
#------------------------------------Interface Demo----------------------

def start_link(socket, mode \\ :interactive, username \\ None, users \\ None, frequency \\ :medium) do
    if mode == :interactive do
        username = IO.gets "Enter username for registration (without @ at start): "
        username = String.trim(username)
        :ets.new(:incomplete_packet, [:set, :public, :named_table, read_concurrency: true])
        spawn fn -> listen(socket, :incomplete_packet) end

    else
        Logger.debug "username given #{username} with frequency:#{frequency}"
    end

    GenServer.start_link(__MODULE__, %{"mode"=> mode, "retweet_prob"=> 10}, name: :"#{username}")

    perform_registration(socket, username)


    if mode == :simulate do
        # subscribe to users
        Logger.debug "performing bulk_subscription for user: #{username} followers: #{inspect(users)}"
        bulk_subscription(socket, users, username)
        :timer.sleep 1000
    end

    if mode == :interactive do
        interactive_client(socket, username)
    else
        simulative_client(socket, username, frequency)
    end
end

def interactive_client(socket, username) do
    option = IO.gets "Choose an action:\n1. Tweet\n2. Hashtag query\n3. Mention query\n4. Subscribe(Implemented in simulator)\n5. Unsubscribe(Implemented in simulator)\n6. Login\n7. Logout\nEnter your choice: "
    case String.trim(option) do
        "1" -> tweet = IO.gets "Enter tweet:"
                send_tweet(socket, String.trim(tweet), username)
        "2" -> hashtag = IO.gets "Enter hashtag to query for: "
                hashtag_query(socket, String.trim(hashtag), username)
        "3" -> mention = IO.gets "Enter the username to look for(begin with @): "
                mention_query(socket, String.trim(mention), username)
        "4" -> user = IO.gets "Enter the username to follow(without @ in beginning): "
                subscribe(socket, String.split(user, [" ", "\n"], trim: true) , username)
        "5" -> user = IO.gets "Enter the username to unsubscribe to(without @ in beginning): "
                unsubscribe(socket, String.split(user, [" ", "\n"], trim: true), username)
        "6" -> perform_login(socket, username)
        "7" -> perform_logout(socket, username)
        _ -> IO.puts "Invalid option. Please try again"
    end
    interactive_client(socket, username)
end

def init(map) do
    {:ok, map}
end

def handle_cast({:mention, tweets}, map) do
    for tweet <- tweets do
        Logger.info "Tweet: #{tweet}"
    end
    {:noreply, map}
end

def handle_cast({:hashtag, tweets}, map) do
    for tweet <- tweets do
        Logger.info "Tweet: #{tweet}"
    end
    {:noreply, map}
end

def handle_cast({:tweet, username, sender, tweet, socket}, map) do
    Logger.info "username:#{username} sender: #{sender} incoming tweet:- #{tweet}"
    # with probability od 10% do retweet
    mode = map["mode"]
    if mode != :interactive and :rand.uniform(100) <= map["retweet_prob"] do
        Logger.debug "username:#{username} doing retweet"
        data = %{"function"=> "tweet", "username"=> username, "tweet"=> tweet}
        send_message(socket, data)
    end
    if mode == :interactive do
        input = IO.gets "Want to retweet(y/n)? "
        input = String.trim(input)
        if input == "y" do
            Logger.debug "username:#{username} doing retweet"
            data = %{"function"=> "tweet", "username"=> username, "tweet"=> tweet}
            send_message(socket, data)
        end
    end
    {:noreply, map}
end

def handle_cast({:feed, feed}, map) do
    Logger.info "Incoming feed which was accumulated while you were offline"
    for item <- feed do
        Logger.info "Tweet: #{item}"
    end
    {:noreply, map}
end


#------------------------------------------Simulation-----------------------------
def simulative_client(socket, username, frequency) do
    #send tweet
    tweet = generate_random_tweet(100)
    Logger.debug "#{username} sending tweet: #{tweet}"
    send_tweet(socket, tweet, username)
    #sleep
    # perform logout
    if frequency == :high do
        :timer.sleep(200)
        simulate_logout(socket, username, frequency)
    else
        if frequency == :medium do
            :timer.sleep(400)
            simulate_logout(socket, username, frequency)
        else
            :timer.sleep(800)
            simulate_logout(socket, username, frequency)
        end
    end
    simulative_client(socket, username, frequency)
end

def simulate(socket, user_count \\ 3) do
    user_set = 1..user_count |> Enum.reduce(MapSet.new, fn(_, acc) -> MapSet.put(acc, generate_random_username()) end)
    constant = zipf_constant(user_count)
    Logger.debug "zipf constant: #{constant}"
    # Top 10%  and bottom 10% of total
    high = round(:math.ceil(user_count * 0.1))
    low = user_count - high

    # table to keep track of incomplete packet and try to use it in next iteration
    # as data is a stream
    packet_table = :ets.new(:incomplete_packet, [:set, :public, read_concurrency: true])

    # central listner
    spawn fn -> listen(socket, packet_table) end

    for {username, pos} <- Enum.with_index(user_set) do
        available_subscribers = MapSet.difference(user_set, MapSet.new([username]))
        subscriber_count = zipf_prob(constant, pos+1, user_count)
        Logger.debug "user: #{username} subscriber_count: #{subscriber_count}"
        subscribers = get_subscribers(available_subscribers, subscriber_count)
        frequency = if (pos + 1) <= high do
                        :high
                    else
                        if (pos + 1) > low do
                            :low
                        else
                            :medium
                        end
                    end
        spawn fn -> start_link(socket, :simulate, username, subscribers, frequency) end
    end
    keep_alive()
end

  def get_subscribers(available_subscribers, subscriber_count) do
      Enum.shuffle(available_subscribers) |> Enum.take(subscriber_count) |> MapSet.new()
  end

def keep_alive() do
    :timer.sleep 10000
    keep_alive()
end

def simulate_logout(socket, username, frequency) do
    random_num = :rand.uniform(100)
    if frequency == :high and random_num <= 3 do
        # autologin is turned true
        perform_logout(socket, username, true)
    else
        if frequency == :medium and random_num <= 5 do
            # autologin is turned true
            perform_logout(socket, username, true)
        else
            if random_num <= 7 do
                # autologin is turned true
                perform_logout(socket, username, true)
            end
        end
    end
end
#----------------------------------------------------------------------------------
#-------------------------------------
def listen(socket, packet_table) do
    {status, response} = :gen_tcp.recv(socket, 0)
    if status == :ok do
        # this will handle the case when there are more than one
        multiple_data = response |> String.split("}", trim: :true)
        for data <- multiple_data do
            Logger.debug "data to be decoded: #{inspect(data)}"
            incomplete_packet = get_incomplete_packet(packet_table)
            if incomplete_packet != false do
                data = "#{incomplete_packet}#{data}"
                Logger.debug "Found incomplete_packet and modified to: #{data}"
            end
            try do
                data = Poison.decode!("#{data}}")
                username = data["username"]
                Logger.debug "received data at user #{username} data: #{inspect(data)}"
                case data["function"] do
                    "register" -> GenServer.cast(:"#{username}", {:register, data})
                    "hashtag" -> GenServer.cast(:"#{username}", {:hashtag, data["tweets"]})
                    "mention" -> GenServer.cast(:"#{username}", {:mention, data["tweets"]})
                    "tweet" -> GenServer.cast(:"#{username}", {:tweet, username, data["sender"], data["tweet"], socket})
                    "feed" -> GenServer.cast(:"#{username}", {:feed, data["feed"]})
                    _ -> Logger.error "unmatched clause for data: #{inspect(data)}"
                end
            rescue
                Poison.SyntaxError -> Logger.debug "Got poison error for data: #{data}"
                insert_incomplete_packet(data, packet_table)
            end
        end
    end
    listen(socket, packet_table)
end

def perform_logout(server, username, autologin \\ false) do
    # send logout message
    data = %{"function"=> "logout", "username"=> username}
    send_message(server, data)
    if autologin do
        # sleep for some random time between 1 to 5000 milliseconds
        sec = :rand.uniform(5000)
        Logger.debug "#{username} sleeping for #{sec} seconds"
        :timer.sleep sec
        # send login back to server
        perform_login(server, username)
    end
end


def perform_login(server, username) do
    data = %{"function"=> "login", "username"=> username}
    Logger.debug "Sending login message to server"
    send_message(server, data)
end

def account_delete(server, username) do
    data = %{"function"=> "account_delete", "username"=> username}
    Logger.debug "Deleting your account..."
    send_message(server, data)
end



def received_tweet(server, username, tweet) do
    # print tweet
    Logger.info "username:#{username} incoming tweet:- #{tweet}"
    # with probability od 10% do retweet
    if :rand.uniform(100) <= 10 do
        Logger.debug "username:#{username} doing retweet"
        data = %{"function"=> "tweet", "username"=> username, "tweet"=> tweet}
        send_message(server, data)
    end
end

def process_feed(feed) do
    Logger.debug "Incoming feed"
    for item <- feed do
        Logger.info "Tweet: #{item}"
    end
end

def send_tweet(socket, tweet, username) do
    data = %{"function"=> "tweet", "username"=> username, "tweet"=> tweet}
    send_message(socket, data)
end

def hashtag_query(socket, hashtag, username) do
    data = %{"function"=> "hashtag", "username"=> username, "hashtag"=> hashtag}
    send_message(socket, data)
end

def mention_query(socket, mention, username) do
    data = %{"function"=> "mention", "mention"=> mention, "username"=> username}
    send_message(socket, data)
end

def subscribe(socket, users, username) do
    data = %{"function"=> "subscribe", "users"=> users, "username"=> username}
    send_message(socket, data)
end

def bulk_subscription(socket, users, username) do
    user_chunk_list = users |> Enum.chunk_every(70)
    for user_list <- user_chunk_list do
        data = %{"function"=> "bulk_subscription", "users"=> user_list, "username"=> username}
        send_message(socket, data)
        :timer.sleep 50
    end
end

  def unsubscribe(socket, users, username) do
    data = %{"function"=> "unsubscribe", "users"=> users, "username"=> username}
    send_message(socket, data)
  end


      def insert_incomplete_packet(data, table)do
         :ets.insert(table, {"incomplete_packet", data})
      end

      def get_incomplete_packet(table) do
          packet = false
          if :ets.member(table, "incomplete_packet") do
              packet = :ets.lookup_element(table, "incomplete_packet", 2)
              :ets.delete(table, "incomplete_packet")
          end
          packet
      end
#----------------------Zipf Distribution-----------------------------------
      def zipf_constant(users) do

          users = for n <- 1..users, do: 1/n
          :math.pow(Enum.sum(users), -1)
      end
      def zipf_prob(constant, user, users) do
          round((constant/user)*users)
      end

      def generate_random_str(len, common_str) do
          list = common_str |> String.split("", trim: true) |> Enum.shuffle
          random_str = 1..len |> Enum.reduce([], fn(_, acc) -> [Enum.random(list) | acc] end) |> Enum.join("")
          random_str
      end

      def generate_random_username(len \\ 10) do
          common_str = "abcdefghijklmnopqrstuvwxyz0123456789"
          generate_random_str(len, common_str)
      end

      def generate_random_tweet(len) do
          common_str = "  abcdefghijklmnopqrstuvwxyz  0123456789"
          generate_random_str(len, common_str)
      end

end
