import { expect, test } from "vitest";
import { greet } from "./greet";

test("greets a name", () => {
  expect(greet("TimberCore")).toBe("Hello, TimberCore!");
});

test("falls back to world when blank", () => {
  expect(greet("  ")).toBe("Hello, world!");
});

// Deliberately wrong: proves CI catches a bad test and the branch gate blocks the merge.
test("DELIBERATELY FAILING - gate proof", () => {
  expect(greet("TimberCore")).toBe("this assertion is wrong on purpose");
});
