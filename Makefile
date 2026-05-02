.PHONY: format lint lint-fix kernels-build kernels-test build test verify release-check check check-direct-mutation-callers check-direct-mutation-budget transcripts check-transcript-coverage check-kernels-test-required check-kernel-abi-goldens regen-kernel-abi-goldens migration-signoff

SWIFT_WITH_GHOSTTY = LIBRARY_PATH="$$(./Scripts/build-preflight.sh print-ghostty-library-dir)$${LIBRARY_PATH:+:$$LIBRARY_PATH}"

format:
	swiftformat .

lint:
	swiftlint lint

lint-fix:
	swiftlint lint --fix

kernels-build:
	./Scripts/build-zig-kernels.sh $(if $(CONFIG),$(CONFIG),debug)

kernels-test:
	cd Zig/omniwm_kernels && zig build test
	@mkdir -p .build
	@touch .build/.kernels-test-passed
	@echo "kernels-test: marker updated at .build/.kernels-test-passed"

build:
	./Scripts/build-preflight.sh build debug
	$(SWIFT_WITH_GHOSTTY) swift build

test:
	./Scripts/build-preflight.sh build debug
	$(SWIFT_WITH_GHOSTTY) swift test

check-direct-mutation-callers:
	./Scripts/check-direct-mutation-callers.sh

check-direct-mutation-budget:
	./Scripts/check-direct-mutation-callers.sh --budget-gate

check-transcript-coverage:
	./Scripts/check-transcript-coverage.sh

check-kernels-test-required:
	./Scripts/check-kernels-test-required.sh

check-kernel-abi-goldens:
	./Scripts/check-kernel-abi-goldens.sh

regen-kernel-abi-goldens:
	./Scripts/build-preflight.sh build debug
	OMNIWM_REGENERATE_KERNEL_ABI_GOLDENS=1 $(SWIFT_WITH_GHOSTTY) swift test --filter "KernelABISchemaGeneratorTests"

transcripts:
	./Scripts/build-preflight.sh build debug
	$(SWIFT_WITH_GHOSTTY) swift test --filter "Transcripts"
	$(MAKE) check-transcript-coverage

verify:
	$(MAKE) lint
	$(MAKE) check-direct-mutation-callers
	$(MAKE) check-transcript-coverage
	$(MAKE) check-kernel-abi-goldens
	$(MAKE) check-kernels-test-required
	$(MAKE) build
	$(MAKE) test

release-check:
	./Scripts/build-preflight.sh release-check
	$(MAKE) verify
	./Scripts/build-universal-products.sh release
	test -x .build/apple/Products/Release/OmniWM
	test -x .build/apple/Products/Release/omniwmctl
	lipo -info .build/apple/Products/Release/OmniWM
	lipo -info .build/apple/Products/Release/omniwmctl

check:
	$(MAKE) verify

# Phase 07 GOV-05 — final sign-off composition. Runs the daily verify
# suite plus the transcript suite, kernels-test, and the direct-mutation
# budget report. The migration-debt budget is sealed at 0; the report also
# prints counted runtime ownership boundaries and explicit non-session
# exemptions so reviewers can spot accidental growth.
migration-signoff:
	@echo "=== Migration sign-off composition (Phase 07 GOV-05) ==="
	$(MAKE) verify
	$(MAKE) transcripts
	$(MAKE) kernels-test
	@echo
	@echo "=== Direct-mutation budget gate (target: 0) ==="
	$(MAKE) check-direct-mutation-budget
	@echo
	@echo "Sign-off complete. The total allowlist budget above must remain 0."
