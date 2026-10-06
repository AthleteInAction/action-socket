# ActionSocket

## Overview
Thread-safe client, designed to work with Rails Action Cable websocket protocol. Uses Swift `AsyncStream` to deliver connection, subscription, and message events.

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

## Limitations
- only works with one channel per instance for now
- have only tested with `ws` and not `wss`

## Usage

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

### with headers
```swift
let url = URL(string: "ws://localhost:3000/cable")!

let headers: [ActionSocket.Header] = [
  ActionSocket.Header(field: "Origin", value: "http://localhost"),
  ActionSocket.Header(field: "X-Device-ID", value: "ABC123")
]

let client = ActionSocket(url, channel: "ExampleChannel", headers: headers)
```

### Event Stream
```swift
let client = ActionSocket("ws://localhost:3000/cable", channel: "ExampleChannel")

client.connect()

@State var isConnected: Bool = false
@State var isSubscribed: Bool = false
@State var socketTask: Task<Void, Never>?

socketTask = Task {
    await event in await client.stream {
        switch event {
        case .connection(let isConnected):
            isConnected = isConnected
        case .subscription(let isSubscribed):
            isSubscribed = isSubscribed
        case .data(let data):
            // data is JSON data for easy decoding via Codable object
        }
    }
}

// if the Task is cancelled, the client will automatically disconnect
// the event stream will end
// you will need to make a manual call to client.connect() to re-connect
socketTask?.cancel()

// if the parent task is cancelled, client.disconnect() is not needed
// client.disconnect() is for manual control and will end the event stream and Task
// client.connect() will need to be called if you wish to re-connect after client.disconnect()
client.disconnect()
```

### Send Message
```swift
let payload: [String: Any?] = [
    "id": 123,
    "name": "Darth Vader",
    "active": true
]

try? await client.send(payload)
```

## Re-Connection Strategy
If the client loses connection, it will automatically attempt to re-connect.
- 1st attempt is immediate
- 2nd attempt waits 1 second
- 3rd attempt waits 2 seconds
- 4th attempt waits 3 seconds
- all subsequent attempts wait 3 seconds until re-connect

## View Example
### Navigation Example
This example is placed in a `NavigationStack` to demonstrate how the client automatically disconnects when the view Task is cancelled on dismiss
```ruby
# Rails

# Action Cable message used in below example
ActionCable.server.broadcast(
    'clips_channel',
    {
        id: 123,
        name: "Darth Vader",
        active: true
    }
)
```

```swift
// Swift

import SwiftUI
import ActionSocket


struct User: Codable {
    let id: Int
    let name: String
    let active: Bool
}


struct NavigationExampleView: View {
    let client = ActionSocket(
        "ws://localhost:3000/cable",
        channel: "ExampleChannel",
        headers: [
            ActionSocket.Header(field: "X-Device-ID", value: "ABC123")
        ]
    )
    
    
    @State var isConnected: Bool = false
    @State var isSubscribed: Bool = false
    @State var user: User?
    
    
    var body: some View {
        VStack(spacing: 20) {
            if let user {
                Text(user.name)
            }
            
            Text(isConnected ? "✅ CONNECTED" : "❌ DISCONNECTED")
            Text(isSubscribed ? "✅ SUBSCRIBED" : "❌ UNSUBSCRIBED")
        }
        // view task is cancelled on view dismissal
        // this will automatically disconnect the
        // client and end the event stream
        .task {
            await connect()
        }
    }
    
    
    func connect() async {
        for await event in await client.stream {
            switch event {
            case .connection(let isConnected):
                self.isConnected = isConnected
            case .subscription(let isSubscribed):
                self.isSubscribed = isSubscribed
            case .data(let data):
                let user = decodeToUser(data: data)
                self.user = user
            }
        }
    }
    
    
    func decodeToUser(data: Data) -> User? {
        let decoder = JSONDecoder()
        let user = try? decoder.decode(User.self, from: data)
        return user
    }
}


struct ParentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: NavigationExampleView()) {
                    Text("Socket View")
                }
            }
        }
    }
}


#Preview {
    ParentView()
}
```
