// Comments may mention catch (...) freely.
int main() {
    try {
        work();
    } catch (const std::exception& error) {
        log(error.what());
        return 1;
    } catch (...) { // boundary: program
        log("unknown exception");
        return 1;
    }
    return 0;
}
