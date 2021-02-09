defmodule Proj41Test do

  use ExUnit.Case
  require Logger
  doctest Proj41

 test " User table Initialization " do
   IO.inspect("TEST: Initializing users ets table at the start")
   Server.initialize_tables()
  assert :ets.whereis(:users) !=:undefined
 end

 test " Hashtag Table Initialization " do
   IO.inspect("TEST: Initializing hashtag ets table at the start.")
   Server.initialize_tables()
   assert :ets.whereis(:hashtags) != :undefined
 end

 test " Mentions Table Initialization " do
   IO.inspect("TEST: Initializing mentions ets table at the start.")
   Server.initialize_tables()
   assert :ets.whereis(:mentions) != :undefined
 end

 test " Counter Record Initialization " do
   IO.inspect("TEST: Initializing Counter records at the start.")
   Server.initialize_tables()
   assert :ets.whereis(:counter) != :undefined
 end

  test " Registration " do
  IO.inspect("TEST:Registration Success")
  Server.initialize_tables()
  assert :ets.member(:users,"Kratos") != true
  end

  test "Hashtags" do
  IO.inspect("TEST:Hashtag Query")
  Server.initialize_tables()
  assert :ets.member(:hashtags,"#{GOW}") != true
  end

  test "Mentions" do
  IO.inspect("TEST:Mentions")
  Server.initialize_tables()
  assert :ets.member(:mentions,"@Kratos") != true
  end

  test "Tweet Counters Initialization" do
  IO.inspect("TEST: Tweet Counter Initialization")
  Server.initialize_tables()
  assert "tweets" != true
  end

  test "Total Users Counter Initialization" do
  IO.inspect("TEST: Users Counter Initialization")
  Server.initialize_tables()
  assert "total_users" !=true
end

  test "Online Users Counters Initialization" do
  IO.inspect("TEST: online Counter Initialization")
  Server.initialize_tables()
  assert "online_users" != true
end

test "Offline users Counters Initialization" do
IO.inspect("TEST: Offline Counter Initialization")
Server.initialize_tables()
assert "offline_users" != true
end

end
