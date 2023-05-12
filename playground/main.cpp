#include <fmt/core.h>

#include <catch2/catch_test_macros.hpp>
#include <coroutine>
#include <exception>
#include <iterator>
#include <tuple>

// NOLINTBEGIN

// Compiler transformation for coroutine:
// T F() {
//     promise_type promise;
//     T return_object = promise.get_return_object();
//     co_await promise.initial_suspend();
//     try {
//         /* coroutine body */
//     } catch (...) {
//         promise.unhandled_exception();
//     }
//     co_await promise.final_suspend();
// }

// Compiler transformation for co_await <expr>:
// auto&& awaiter = <expr>;
// if (!awaiter.await_ready()) {
//     Может вернуть результат:
//     awaiter.await_suspend(handle_t::from_promise(promise));
//
//     Здесь может быть проверка результата:
//     <suspend + yield if required>
//
//     В эту точку возвращаемся:
//     <resume point>
// }
// Тоже может вернуть результат:
// awaiter.await_resume();

// co_yield <expr> -> co_await promise.yield_value(<expr>)

// Это объект, который вернётся из корутины
struct Resumable {
    // Интерфейс корутины требует наличие в нём этого подтипа
    struct promise_type {
        using coro_handle = std::coroutine_handle<promise_type>;

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
        // return_void(), потому что в Foo() нет co_return <some_value>, то есть ничего не возвращаем
        // unhandled_exception()

        // Можно пропустить:
        // yield_value(), потому что в Foo() нет co_yield
        // return_value(), потому что в Foo() нет co_return <some_value>
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
        if (handle_ != nullptr) {
            handle_.destroy();
        }
    }

 private:
    promise_type::coro_handle handle_;
};

Resumable Foo() {
    fmt::print("Hello ");
    co_await std::suspend_always();
    fmt::print("World\n");
}

template <typename T>
struct Generator {
    struct promise_type {
        using coro_handle = std::coroutine_handle<promise_type>;

        auto get_return_object() {
            return Generator(coro_handle::from_promise(*this));
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

        auto yield_value(T value) {
            value_ = value;
            return std::suspend_always();
        }

        T value_;
    };

    using coro_handle = typename promise_type::coro_handle;

    explicit Generator(coro_handle handle)
        : handle_(handle) {
    }

    Generator(Generator&& rhs)
        : handle_(rhs.handle_) {
        rhs.handle_ = nullptr;
    }

    Generator(const Generator&) = delete;

    bool MoveNext() {
        if (!handle_.done()) {
            handle_.resume();
        }
        return !handle_.done();
    }

    T CurrentValue() {
        return handle_.promise().value_;
    }

    ~Generator() {
        if (handle_ != nullptr) {
            handle_.destroy();
        }
    }

 private:
    coro_handle handle_;
};

Generator<int> NaturalNums() {
    int num = 0;
    while (true) {
        co_yield num;
        ++num;
    }
}

template <typename T>
struct RangeGenerator {
    struct promise_type {
        using coro_handle = std::coroutine_handle<promise_type>;

        auto get_return_object() {
            return RangeGenerator(coro_handle::from_promise(*this));
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

        auto yield_value(const T& value) {
            value_ = &value;
            return std::suspend_always();
        }

        const T* value_ = nullptr;
    };

    using coro_handle = typename promise_type::coro_handle;

    struct iterator {
        using iterator_category = std::forward_iterator_tag;
        using value_type = T;
        using difference_type = ptrdiff_t;
        using pointer = const T*;
        using reference = const T&;

        explicit iterator(coro_handle handle)
            : handle_(handle) {
        }

        iterator& operator++() {
            handle_.resume();
            if (handle_.done()) {
                handle_ = nullptr;
            }
            return *this;
        }

        reference operator*() const {
            return *handle_.promise().value_;
        }

        pointer operator->() const {
            return handle_.promise().value_;
        }

        auto operator<=>(const iterator& rhs) const noexcept = default;

        coro_handle handle_;
    };

    explicit RangeGenerator(coro_handle handle)
        : handle_(handle) {
    }

    RangeGenerator(RangeGenerator&& rhs)
        : handle_(rhs.handle_) {
        rhs.handle_ = nullptr;
    }

    RangeGenerator(const RangeGenerator&) = delete;

    iterator begin() {
        if (handle_ == nullptr) {
            return iterator(nullptr);
        }
        handle_.resume();
        if (handle_.done()) {
            return iterator(nullptr);
        }
        return iterator(handle_);
    }

    iterator end() {
        return iterator(nullptr);
    }

    ~RangeGenerator() {
        if (handle_ != nullptr) {
            handle_.destroy();
        }
    }

 private:
    coro_handle handle_;
};

template <typename T>
RangeGenerator<T> Sequence(T begin, T end, T step) {
    for (T num = begin; num < end; num += step) {
        co_yield num;
    }
}

template <typename T, typename U>
RangeGenerator<std::tuple<T, U>> Zip(RangeGenerator<T> t, RangeGenerator<U> u) {
    auto itt = t.begin();
    auto jtt = t.end();
    auto itu = u.begin();
    auto jtu = u.end();

    while (itt != jtt && itu != jtu) {
        co_yield std::make_tuple(*itt, *itu);
        ++itt;
        ++itu;
    }
}

TEST_CASE("Sequence") {
    int i = 0;
    for (int x : Sequence(0, 100, 5)) {
        REQUIRE(i == x);
        i += 5;
    }
}

TEST_CASE("Zip") {
    int i = 0;
    int j = 0;
    for (auto [x, y] : Zip(Sequence(0, 100, 5), Sequence(0, 100, 6))) {
        REQUIRE(i == x);
        REQUIRE(j == y);
        i += 5;
        j += 6;
    }
}

// NOLINTEND
