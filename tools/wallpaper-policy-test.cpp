#include <cassert>
#include <future>
#include <iostream>

#include "system/wallpaper_write_policy.hpp"

int main() {
	using qs::windows::sys::WallpaperWritePolicy;
	WallpaperWritePolicy policy;
	auto original = policy.token();
	assert(policy.allows(original));
	assert(!policy.external());
	assert(!policy.setExternal(false));
	assert(policy.allows(original));

	std::promise<void> release;
	auto ready = release.get_future().share();
	auto queued = std::async(std::launch::async, [&policy, ready, original] {
		ready.wait();
		return policy.allows(original);
	});
	assert(policy.setExternal(true));
	assert(policy.external());
	assert(!policy.allows(policy.token()));
	assert(!policy.allows(original));
	assert(!policy.setExternal(true));
	assert(policy.setExternal(false));
	assert(!policy.external());
	assert(policy.allows(policy.token()));
	assert(!policy.allows(original));
	release.set_value();
	assert(!queued.get());
	std::cout << "PASS: external ownership, idempotent changes, stale queued writes and managed re-entry\n";
}
