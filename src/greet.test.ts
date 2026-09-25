import { expect, test } from "vitest";
import { greet } from "./greet";

test("greets a name", () => {
  expect(greet("TimberCore")).toBe("Hello, TimberCore!");
});

test("falls back to world when blank", () => {
  expect(greet("  ")).toBe("Hello, world!");
});

// Frontend-only failure: backend should still run green and report separately.
test("DELIBERATELY FAILING - frontend only", () => {
  expect(greet("x")).toBe("wrong on purpose");
});
