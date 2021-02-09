# Twitter Simulator

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `proj4_1` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:proj4_1, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/proj4_1](https://hexdocs.pm/proj4_1).

#### WHAT IS WORKING
Run the following commands from the directory containing mix.exs:
• Run mix deps.get to build all the dependencies.
• mix escript.build
• Run escript ./project4_1 server to start the server in command line .
• Run escript ./proj4 simulate 127.0.0.1 num_user num_msg to run the simulator in a
different command line window.
Where num_user represents the number of users created by the simulator, num_msg
represents the number of tweets made by that user.
• Run escript ./project4_1 client 127.0.0.1 to start the client interface in command line .
[Run either “simulator” or “client” at a given time. “client” provides an interface of the
system. All functionalities are implemented within the simulation.]

#### FUNCTIONALITIES IMPLEMENTED
• We were able to register and delete the account.
• We were able to log in and log out.
• We were able to send the tweets and the tweets included hashtags.
• We were able to subscribe to user’s tweets .
• We were able to implement Re-tweets.
• We were able to implement querying tweets subscribed to, tweets with specific hashtags,
tweets in which the user is mentioned.
• We were able to deliver the above types of tweets live without querying when user is
online. When user is offline the tweets get stored in user’s feed.
