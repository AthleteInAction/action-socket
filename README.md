# ActionSocket

## Overview
Thread-safe client, designed to work with Rails Action Cable websocket protocol. Uses Swift AsyncStream to deliver connection, subscription, and message events.

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
        case .isConnected(let isConnected):
            // use main thread to update UI items
            Task { @MainActor in
                self.isConnected = isConnected
            }
        case .isSubscribed(let isSubscribed):
            // use main thread to update UI items
            Task { @MainActor in
                self.isSubscribed = isSubscribed
            }
        case .data(let data):
            // use main thread to update UI items
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
    let client = ActionSocket("ws://localhost:3000/cable", channel: "ExampleChannel")
    
    
    @State var isConnected: Bool = false
    @State var isSubscribed: Bool = false
    @State var user: User?
    
    
    var body: some View {
        VStack(spacing: 20) {
            Text(isConnected ? "✅ CONNECTED" : "❌ DISCONNECTED")
            Text(isSubscribed ? "✅ SUBSCRIBED" : "❌ UNSUBSCRIBED")
            
            // if client is connected, client.connect()
            // will do nothing
            Button("MANUAL CONNECT"){
                Task { await connect() }
            }
            .foregroundColor(.green)
            
            // on manual disconnect, client will not
            // attempt to re-connect again until
            // client.connect() is called
            Button("DISCONNECT", role: .destructive){
                Task { await client.disconnect() }
            }
        }
        // view task is cancelled on view dismiss
        // this will automatically disconnect the
        // client and end the event stream
        .task {
            await connect()
        }
    }
    
    
    func connect() async {
        for await event in await client.stream {
            switch event {
            case .isConnected(let isConnected):
                self.isConnected = isConnected
            case .isSubscribed(let isSubscribed):
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
