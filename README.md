# Kioto

Concurrency library for Zig

## Features

- Orthogonal basis for concurrency: _runtime_ × _fibers_ × _futures_
- Stackful fibers with stack pooling
- Functional futures with combinators

## Contents

- [Runtime](kioto/runtime)
  - Multi-threaded `ConcurrentRuntime`
  - Deterministic `ManualRuntime` for testing and debugging
  - Timers
- [Futures](kioto/futures)
  - Constructors
    - `spawn`
    - `ready`
    - `unit`
  - Combinators
    - Sequential composition
      - `map` – maps a value of type `T` to type `U`
      - `flatten` – flattens nested futures (for asynchronous mappers)
      - `flatMap` – `Map` + `Flatten`
      - `via` – sets runtime for mappers
      - `after` – attaches timeout
    - Parallel composition
      - `both`
      - `first`
  - Terminators
    - `get` – unwraps value from future, blocks thread
    - `await` – unwraps value from future, does not block thread
- [Stackful Fibers](kioto/fibers)
  - Scheduling
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
