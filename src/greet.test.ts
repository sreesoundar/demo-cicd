import { expect, test } from "vitest";
import { greet } from "./greet";

test("greets a name", () => {
  expect(greet("TimberCore")).toBe("Hello, TimberCore!");
});

test("falls back to world when blank", () => {
  expect(greet("  ")).toBe("Hello, world!");
});
