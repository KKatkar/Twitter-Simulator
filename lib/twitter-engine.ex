defmodule Server do
    use GenServer
    require Logger

    def start_link(port) do
        Logger.debug "occupying the socket"
        {:ok, listen_socket} = :gen_tcp.listen(port,[:binary,
                                                    {:ip, {0,0,0,0}},
                                                    {:packet, 0},
                                                    {:active, false},
                                                    {:reuseaddr, true}])
        Logger.debug "socket connection established"
        initialize_tables()
        initialize_counters()
        GenServer.start_link(__MODULE__, listen_socket, name: :twitterEngine)
        spawn fn -> statistics() end
        loop_acceptor(listen_socket)
    end

    def initialize_tables() do
        Logger.debug "generating tables"
        Logger.debug "generating hashtags table"
        :ets.new(:hashtags, [:set, :public, :named_table, read_concurrency: true])
        Logger.debug "generating mentions table"
        :ets.new(:mentions, [:set, :public, :named_table, read_concurrency: true])
        Logger.debug "generating users table"
        # {username, status, subscribers, feed, port}
        :ets.new(:users, [:set, :public, :named_table, read_concurrency: true])
        Logger.debug "generating counter record"
        :ets.new(:counter, [:set, :public, :named_table, read_concurrency: true])
    end

    def initialize_counters() do
        insert_record(:counter, {"tweets", 0})
        insert_record(:counter, {"total_users", 0})
        insert_record(:counter, {"online_users", 0})
        insert_record(:counter, {"offline_users", 0})
    end

    def serve(worker, incomplete_packet) do
        {status, response} = :gen_tcp.recv(worker, 0)
        if status == :ok do
            # this will handle the case when there are more than one
            multiple_data = response |> String.split("}", trim: :true)
            for data <- multiple_data do
                incomplete_packet_data = get_incomplete_packet(incomplete_packet)
                if incomplete_packet_data != false do
                    data = "#{incomplete_packet_data}#{data}"
                  end
                try do
                    data = Poison.decode!("#{data}}")

                    case Map.get(data, "function") do
                       "register" -> GenServer.cast(:twitterEngine, {:register, data["username"], worker})
                       "login" -> GenServer.cast(:twitterEngine, {:login, data["username"], worker})
                       "logout" -> GenServer.cast(:twitterEngine, {:logout, data["username"]})
                       "hashtag" -> GenServer.cast(:twitterEngine, {:hashtag, data["hashtag"], data["username"], worker})
                       "mention" -> GenServer.cast(:twitterEngine, {:mention, data["mention"], data["username"], worker})
                       "tweet" -> GenServer.cast(:twitterEngine, {:tweet, data["username"], data["tweet"]})
                       "subscribe" -> GenServer.cast(:twitterEngine, {:subscribe, data["username"], data["users"]})
                       "unsubscribe" -> GenServer.cast(:twitterEngine, {:unsubscribe, data["username"], data["users"]})

                       "bulk_subscription" -> GenServer.cast(:twitterEngine, {:bulk_subscription, data["username"], data["users"]})
                       _ -> Logger.error "unmatched clause for data: #{inspect(data)}"
                    end
                rescue
                    Poison.SyntaxError -> Logger.debug "Got poison error for data: #{data}"
                    insert_record(incomplete_packet, {"incomplete_packet", data})
                end
            end
        end
        serve(worker, incomplete_packet)
    end
#---------------------------------------Display Server statistics--------------------------------------
    def statistics(period \\ 10000, last_tweet_count \\ 0) do
        :timer.sleep period
        current_tweet_count = :ets.lookup_element(:counter, "tweets", 2)
        tweet_per_sec = (current_tweet_count - last_tweet_count) / (10000 / 1000)
        total_users = :ets.lookup_element(:counter, "total_users", 2)
        online_users = :ets.lookup_element(:counter, "online_users", 2)
        offline_users = :ets.lookup_element(:counter, "offline_users", 2)
        Logger.info "Twitter-engine (Statistics)\nTweets(per sec): #{tweet_per_sec}\nTotal Users: #{total_users}\nOnline Users: #{online_users}\nOffline Users: #{offline_users}"
        statistics(period, current_tweet_count)
    end
#---------------------------------------------------------------------------
    def loop_acceptor(socket) do
        Logger.debug "Ready to accept new connections"
        {:ok, worker} = :gen_tcp.accept(socket)
        incomplete_packet = :ets.new(:incomplete_packet, [:set, :public, read_concurrency: true])
        spawn fn -> serve(worker, incomplete_packet) end
        loop_acceptor(socket)
    end
#-----------------------------------------------------------------------------

def send_response(client, data) do
    encoded_response = Poison.encode!(data)
    :gen_tcp.send(client, encoded_response)
end


def send_tweet(to, sender, tweet) do
    #Logger.debug "in send_tweet"
    port = get_user_port(to)
    status = get_user_status(to)
    if status == :online do
        #Logger.debug "Sending to: #{to} tweet: #{tweet} on socket: #{inspect(port)}"
        send_response(port, %{"function"=> "tweet", "sender"=> sender, "tweet"=> tweet, "username"=> to})
    else
        #Logger.debug "Adding to user feed as #{to} is not online"
        add_user_feed(to, tweet)
    end
    increase_counter("tweets")
end

def get_incomplete_packet(table) do
    packet = false
    if :ets.member(table, "incomplete_packet") do
        packet = :ets.lookup_element(table, "incomplete_packet", 2)
        :ets.delete(table, "incomplete_packet")
    end
    packet
end

def update_counter(field, factor) do
    :ets.update_counter(:counter, field, factor)
end

def increase_counter(field) do
    update_counter(field, 1)
end

def decrease_counter(field) do
    update_counter(field, -1)
end

def member_of_mentions(mention) do
    :ets.member(:mentions, mention)
end

def get_mention_tweets(mention) do
    if member_of_mentions(mention) do
        :ets.lookup_element(:mentions, mention, 2)
    else
        MapSet.new
    end
end

def add_mention_tweet(mention, tweet) do
    mentions = :ets.lookup(:mentions, mention)
    if mentions != [] do
        updated_mentions = mentions |> List.first |> elem(1) |> MapSet.put(tweet)
        insert_record(:mentions, {mention, updated_mentions})
    else
        tweets = MapSet.new |> MapSet.put(tweet)
        insert_record(:mentions, {mention, tweets})
    end
end

def send_mentions(mention, client, username) do
    tweets_chunks = get_mention_tweets(mention) |> MapSet.to_list() |> Enum.chunk_every(5)
    #Logger.debug "sending mentions: #{inspect(tweets_chunks)}"
    for tweets <- tweets_chunks do
        data = %{"function"=> "mention", "tweets" => tweets, "username" => username}
        send_response(client, data)
        :timer.sleep 20
    end
end

def member_of_hashtags(hashtag) do
    :ets.member(:hashtags, hashtag)
end

def get_hashtag_tweets(hashtag) do
    if member_of_hashtags(hashtag) do
        :ets.lookup_element(:hashtags, hashtag, 2)
    else
        MapSet.new
    end
end

def add_hashtag_tweet(hashtag, tweet) do
    hashtags = :ets.lookup(:hashtags, hashtag)
    if hashtags != [] do
        updated_tweets = hashtags |> List.first |> elem(1) |> MapSet.put(tweet)
        insert_record(:hashtags, {hashtag, updated_tweets})
    else
        tweets = MapSet.new |> MapSet.put(tweet)
        insert_record(:hashtags, {hashtag, tweets})
    end
end

def send_hashtags(hashtag, client, username) do
    tweets_chunks = get_hashtag_tweets(hashtag) |> MapSet.to_list() |> Enum.chunk_every(5)
    for tweets <- tweets_chunks do
        data = %{"function"=> "hashtag", "tweets" => tweets, "username" => username}
        send_response(client, data)
        :timer.sleep 20
    end
end

def member_of_users(username) do
    :ets.member(:users, username)
end

def insert_record(table, tuple) do
    :ets.insert(table, tuple)
end

def user_has_feeds(username) do
    feed = get_user_feed(username)
    if feed == :queue.new do
      false
    else
      true
    end
end

def send_feed(username, client) do
    feeds = get_user_feed(username) |> :queue.to_list |> Enum.chunk_every(5)
    for feed <- feeds do
        data = %{"function"=> "feed", "feed" => feed, "username"=> username}
        send_response(client, data)
        :timer.sleep 50
    end
    empty_user_feed(username)
end

def get_user(username) do
    record = :ets.lookup(:users, username)
    if record == [] do
      false
    else
      List.first(record)
    end
end

def get_user_field(username, pos) do
    user = get_user(username)
    if user != false do
      user |> elem(pos)
    else
      false
    end
end

def get_user_status(username) do
    #{status, subscribers, feed}
    get_user_field(username, 1)
end

def get_user_subscribers(username) do
    get_user_field(username, 2)
end

def get_user_feed(username) do
    get_user_field(username, 3)
end

def get_user_port(username) do
    get_user_field(username, 4)
end

def update_user_field(username, pos, value) do
    :ets.update_element(:users, username, {pos, value})
end

def update_user_status(username, status) do
    update_user_field(username, 2, status)
end

def add_user_subscribers(username, subscriber) do
    subs = get_user_subscribers(username) |> MapSet.put(subscriber)
    Logger.debug "user: #{username} updated subs: #{inspect(subs)}"
    update_user_field(username, 3, subs)
end

def add_bulk_user_subscribers(username, follwers) do
    existing_subs = get_user_subscribers(username)
    subs = MapSet.union(existing_subs, MapSet.new(follwers))
    Logger.debug "user: #{username} updated subs: #{inspect(subs)}"
    update_user_field(username, 3, subs)
end

def remove_user_subscriber(username, subscriber) do
    subs = get_user_subscribers(username) |> MapSet.delete(subscriber)
    update_user_field(username, 3, subs)
end

def add_user_feed(username, tweet) do
    feed = get_user_feed(username)
    if feed do
        #Logger.debug "#{username}'s feed: #{inspect(feed)}"
        feed = enqueue(feed, tweet)
        #Logger.debug "#{username}'s updated feed: #{inspect(feed)}"
        update_user_field(username, 4, feed)
    end
end

def empty_user_feed(username) do
    update_user_field(username, 4, :queue.new)
end

def enqueue(queue, value) do
    if :queue.member(value, queue) do
        queue
    else
        :queue.in(value, queue)
    end
end
#-------------------GenServer function----------------------
def init(listen_socket) do
    {:ok, listen_socket}
end

def handle_cast({:register, username, client}, listen_socket) do
    user = get_user(username)

    if user != false do
        send_response(client, %{"function"=> "register", "username"=> username, "status"=> "error", "message"=> "Username already exists"})
    else
        #Logger.debug "added new user: #{username} to set with socket: #{inspect(client)}"

        insert_record(:users, {username, :online, MapSet.new, :queue.new, client})

        increase_counter("total_users")
        increase_counter("online_users")
    end
    {:noreply, listen_socket}
end

def handle_cast({:login, username, client}, listen_socket) do
    if member_of_users(username) do
        offline_users = :ets.lookup_element(:counter, "offline_users", 2)
        if offline_users > 0 do
            decrease_counter("offline_users")
        end
        update_user_status(username, :online)
        if user_has_feeds(username) do
            #Logger.debug "#{username} has some tweets in feed"
            spawn fn ->  send_feed(username, client) end
        end
        increase_counter("online_users")
    end
    {:noreply, listen_socket}
end

def handle_cast({:logout, username}, listen_socket) do
    if member_of_users(username) do
        update_user_status(username, :offline)
        increase_counter("offline_users")
        decrease_counter("online_users")
    end
    {:noreply, listen_socket}
end
################################################################

def handle_cast({:account_delete, username}, listen_socket) do
  if member_of_users(username) do

      :ets.update_element(:counter,"offline_users", 0 )
      :ets.update_element(:counter,"online_users", 0 )
      :timer.sleep 10000
      Log.debug "Account deleted"
      :ets.delete(:users, username)
    end
    {:noreply, listen_socket}
end
###############################################################

def handle_cast({:hashtag, hashtag, username, client}, listen_socket) do
    #Logger.debug "sending tweets containing hashtag: #{hashtag} to user: #{username}"
    spawn fn -> send_hashtags(hashtag, client, username) end
    {:noreply, listen_socket}
end

def handle_cast({:mention, mention, username, client}, listen_socket) do
    #Logger.debug "sending tweets containing mention: #{mention} to user: #{username}"
    spawn fn -> send_mentions(mention, client, username) end
    {:noreply, listen_socket}
end

def handle_cast({:tweet, username, tweet}, listen_socket) do
    mentionedUsers = None
    components = SocialParser.extract(tweet,[:hashtags,:mentions])
    if Map.has_key? components, :hashtags do
        hashTagValues = components[:hashtags]
        for hashtag <- hashTagValues do
            #Logger.debug "adding hashtag :#{hashtag} to hashtags table for tweet: #{tweet}"
            add_hashtag_tweet(hashtag, tweet)
        end
    end

    if Map.has_key?(components, :mentions) do
        mentionedUsers = components[:mentions]
        for user <- mentionedUsers do
            #Logger.debug "adding mention: #{user} to mentions table for tweet: #{tweet}"
            add_mention_tweet(user, tweet)
            mentioned_user = String.split(user, ["@", "+"], trim: true) |> List.first
            if mentioned_user != username do
                send_tweet(mentioned_user, username, tweet)
            end
        end
        mentionedUsers = mentionedUsers |> Enum.reduce([], fn(x, acc) -> [List.first(String.split(x, ["@", "+"], trim: true)) |acc] end)
    end
    subscribers = get_user_subscribers(username)
    for subscriber <- subscribers do
        #Logger.debug "subscribers: #{subscriber} mentioned_users: #{inspect(mentionedUsers)}"
        if mentionedUsers != None and Enum.member?(mentionedUsers, subscriber) do
            #Logger.debug "Not sending the message again"
        else
            send_tweet(subscriber, username, tweet)
        end
    end

    {:noreply, listen_socket}
end

def handle_cast({:subscribe, username, follow}, listen_socket) do
    for sub <- follow do
        Logger.debug "subscribing user: #{username} to: #{sub}"
        add_user_subscribers(sub, username)
    end
    {:noreply, listen_socket}
end

def handle_cast({:bulk_subscription, username, follwers}, listen_socket) do
    #Logger.debug "adding bulk followers for user: #{username}"
    add_bulk_user_subscribers(username, follwers)
    {:noreply, listen_socket}
end

def handle_cast({:unsubscribe, username, unsubscribe}, listen_socket) do
    for unsub <- unsubscribe do
        remove_user_subscriber(unsub, username)
    end
    {:noreply, listen_socket}
end

end
