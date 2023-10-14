#include <thread>
#include <vector>

namespace kioto {

class WorkStealingThreadPool {
 public:
 private:
    std::vector<std::thread> workers_;
};

}