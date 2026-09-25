// POLICY 2.6: conversion operators must be explicit.
// EXPECT: cppcoreguidelines-explicit-constructor
class Flag {
public:
    operator bool() const { return value_; }

private:
    bool value_ = false;
};
