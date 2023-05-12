#include <__coroutine/coroutine_handle.h>
#include <__coroutine/trivial_awaitables.h>
#include <fmt/core.h>

#include <coroutine>
#include <exception>

// Compiler transformation
// generator natural_nums() {
//     promise_type promise;
//     generator return_object = promise.get_return_object();
//     co_await promise.initial_suspend();
//     try {
//         /* coroutine body */
//     } catch (...) {
//         promise.unhandled_exception();
//     }
//     co_await promise.final_suspend();
// }

// int NaturalNums() {
//     int num = 0;
//     while (true) {
//         co_yield num;
//         ++num;
//     }
// }

// Это объект, который вернётся из корутины
struct Resumable {
    // Интерфейс корутины требует наличие в нём этого подтипа
    // NOLINTNEXTLINE
    struct promise_type {
        // NOLINTNEXTLINE
        using coro_handle = std::coroutine_handle<promise_type>;

        // NOLINTNEXTLINE
        auto get_return_object() {
            return Resumable(coro_handle::from_promise(*this));
        }

        auto initial_suspend() noexcept {
            return std::suspend_always();
        }

        auto final_suspend() noexcept {
            return std::suspend_always();
        }

        void return_void() {
        }

        void unhandled_exception() {
            std::terminate();
        }

        // Здесь нужно реализовать:
        // get_return_object()
        // initial_suspend()
        // final_suspend()
        // return_void(), потому что в Foo() нет co_return some_value, то есть ничего не возвращаем
        // unhandled_exception()

        // Можно пропустить:
        // yield_value(), потому что в Foo() нет co_yield
        // return_value(), потому что в Foo() нет co_return some_value
    };

    explicit Resumable(promise_type::coro_handle handle)
        : handle_(handle) {
    }

    Resumable(Resumable&& rhs)
        : handle_(rhs.handle_) {
        rhs.handle_ = nullptr;
    }

    Resumable(const Resumable&) = delete;

    bool Resume() {
        if (!handle_.done()) {
            handle_.resume();
        }
        return !handle_.done();
    }

    ~Resumable() {
        handle_.destroy();
    }

 private:
    promise_type::coro_handle handle_;
};

Resumable Foo() {
    fmt::print("Hello ");
    co_await std::suspend_always();
    fmt::print("World\n");
}

int main() {
    // auto nums = NaturalNums();

    // nums.move_next();
    // auto x = nums.current_value();
    // nums.move_next();
    // auto y = nums.current_value();

    // fmt::print("{} {}\n", x, y);

    Resumable handle = Foo();
    handle.Resume();
    handle.Resume();
    return 0;
}
