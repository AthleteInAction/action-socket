# ActionSocket

## Overview
Thread-safe client designed to work with Rails Action Cable websocket protocol. Uses Swift AsyncStream to deliver connection, subscription, and message events.

## Requirements
- iOS 18+
- macOS 26+

Rails Action Cable must broadcast JSON data. It must not broadcast a single data type, such as an `Integer` or `String`:
```ruby
# Rails

# WILL WORK ------------------------------
params = {
  id: 123,
  username: "Darth Vader",
  active: true
}

ActionCable.server.broadcast(
  'clips_channel',
  params
)
# ----------------------------------------


# !!! WILL NOT WORK !!!!!!!!!!!!!!!!!!!!!!
user_id = 123
ActionCable.server.broadcast(
  'clips_channel',
  user_id
)
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
```

## Instantiate

### Module
```swift
import ActionSocket
```

### with string URL
```swift
let client = ActionSocket("ws://localhost:3000/cable", channel: "ExampleChannel")
```

### with URL object
```swift
let url = URL(string: "ws://localhost:3000/cable")!

let client = ActionSocket(url, channel: "ExampleChannel")
```

### with config and headers
```swift
let url = URL(string: "ws://localhost:3000/cable")!

let headers: [ActionSocket.Header] = [
  ActionSocket.Header(field: "Origin", value: "http://localhost"),
  ActionSocket.Header(field: "X-Device-ID", value: "ABC123")
]

let config = ActionSocket.Config(url: url, channel: "ExampleChannel", headers: headers)

let client = ActionSocket(config: config)
```