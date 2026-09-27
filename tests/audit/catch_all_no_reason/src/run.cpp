int run() {
    try {
        work();
    } catch (...) {
        return 1;
    }
    try {
        work();
    } catch(...) { // swallowed
        return 2;
    }
    return 0;
}
