# Kioto

Concurrency library for Zig

## Features

Orthogonal abstractions for concurrency: _runtime_ × _fibers_ × _futures_:
- [Runtime](kioto/runtime)
  - Multi-threaded `ConcurrentRuntime`
  - Deterministic `ManualRuntime` for testing and debugging
  - Timers
- [Functional futures with combinators](kioto/futures)
  - Constructors
    - `makeContract`
    - `spawn`
    - `ready`
    - `unit`
  - Combinators
    - Sequential composition
      - `map` – maps a value of type `T` to type `U`
      - `flatten` – flattens nested futures (for asynchronous mappers)
      - `flatMap` – `Map` + `Flatten`
      - `via` – sets runtime for mappers
      - `after` – sets delay
    - Parallel composition
      - `both`
      - `first`
  - Terminators
    - `get` – unwraps value from future, blocks thread
    - `await` – unwraps value from future, does not block thread
- [Stackful fibers with stack pooling](kioto/fibers)
  - Api
    - `yield`
    - `sleepFor`
    - `suspendFiber`
    - `spawn`
  - Synchronization
    - `Mutex`
    - `Event`
    - `WaitGroup`
    - `BufferedChannel`
    - `UnbufferedChannel`

## Requirements

|                  | _Supported_       |
|------------------|-------------------|
| Architecture     | x86-64            |
| Operating System | Linux             |
| Compiler         | Zig 0.14.0        |

## Build

```shell
# Clone repo
git clone https://github.com/Tau-0/kioto.git
cd kioto
# Run playground
zig build -Doptimize=ReleaseFast playground
# Run tests
zig build test
```
## Thanks

Roman Lipovsky for the amazing course "Theory and Practice of Concurrency"
