import assert from "node:assert/strict";
import test from "node:test";

import { assertUploadedFileSignature } from "../shared/utils/upload.js";

const pngHeader = Buffer.from("89504e470d0a1a0a0000000d49484452", "hex");
const pdfHeader = Buffer.from("%PDF-1.7", "utf8");

test("assertUploadedFileSignature accepts valid image magic bytes", () => {
  const result = assertUploadedFileSignature(
    {
      originalname: "avatar.png",
      buffer: pngHeader,
    },
    "image"
  );

  assert.equal(result.ok, true);
  assert.equal(result.detectedMime, "image/png");
});

test("assertUploadedFileSignature rejects disguised uploads by content", () => {
  assert.throws(
    () =>
      assertUploadedFileSignature(
        {
          originalname: "avatar.jpg",
          buffer: pdfHeader,
        },
        "image"
      ),
    /INVALID_IMAGE_TYPE/
  );
});
