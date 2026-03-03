import { buildUploadedFileUrl } from "../../shared/utils/upload.js";
import * as service from "./feed.service.js";
import {
  validateCreateStory,
  validateCreateComment,
  validateCreatePost,
  validateCreateThread,
  validateListStories,
  validateListMessages,
  validateListPosts,
  validateMerchantSearch,
  validatePostId,
  validateStoryId,
  validateUserId,
  validateSendMessage,
  validateThreadId,
} from "./feed.validators.js";

function badRequest(res, fields) {
  return res.status(400).json({
    message: "VALIDATION_ERROR",
    fields,
  });
}

export async function listPosts(req, res, next) {
  try {
    const v = validateListPosts(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.listPosts(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listStories(req, res, next) {
  try {
    const v = validateListStories(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.listStories(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getPostById(req, res, next) {
  try {
    const v = validatePostId(req.params.postId);
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.getPostById(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getUserProfile(req, res, next) {
  try {
    const v = validateUserId(req.params.userId);
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.getUserProfile(req.userId, v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listUserPosts(req, res, next) {
  try {
    const user = validateUserId(req.params.userId);
    if (!user.ok) return badRequest(res, user.errors);
    const query = validateListPosts(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listUserPosts(req.userId, user.value, query.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createPost(req, res, next) {
  try {
    const body = {
      ...req.body,
      postKind: req.body?.postKind || req.body?.post_kind,
    };
    const v = validateCreatePost(body);
    if (!v.ok) return badRequest(res, v.errors);

    const media = req.file
      ? {
          url: buildUploadedFileUrl(req, req.file),
          mimetype: req.file.mimetype,
        }
      : null;
    const post = await service.createPost(req.userId, v.value, media);
    return res.status(201).json({ post });
  } catch (error) {
    return next(error);
  }
}

export async function createStory(req, res, next) {
  try {
    const v = validateCreateStory(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);

    const media = req.file
      ? {
          url: buildUploadedFileUrl(req, req.file),
          mimetype: req.file.mimetype,
        }
      : null;

    const story = await service.createStory(req.userId, v.value, media);
    return res.status(201).json({ story });
  } catch (error) {
    return next(error);
  }
}

export async function markStoryViewed(req, res, next) {
  try {
    const v = validateStoryId(req.params.storyId);
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.markStoryViewed({
      storyId: v.value,
      userId: req.userId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function toggleLike(req, res, next) {
  try {
    const v = validatePostId(req.params.postId);
    if (!v.ok) return badRequest(res, v.errors);

    const out = await service.toggleLike({
      postId: v.value,
      userId: req.userId,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listPostComments(req, res, next) {
  try {
    const post = validatePostId(req.params.postId);
    if (!post.ok) return badRequest(res, post.errors);
    const query = validateListMessages(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listComments(post.value, query.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function addComment(req, res, next) {
  try {
    const post = validatePostId(req.params.postId);
    if (!post.ok) return badRequest(res, post.errors);
    const body = validateCreateComment(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.addComment({
      postId: post.value,
      userId: req.userId,
      body: body.value.body,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listMerchants(req, res, next) {
  try {
    const v = validateMerchantSearch(req.query || {});
    if (!v.ok) return badRequest(res, v.errors);
    const out = await service.listMerchantOptions(v.value);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listThreads(req, res, next) {
  try {
    const out = await service.listThreads(req.userId);
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createThread(req, res, next) {
  try {
    const v = validateCreateThread(req.body || {});
    if (!v.ok) return badRequest(res, v.errors);
    const thread = await service.createThread({
      userId: req.userId,
      otherUserId: v.value.userId,
    });
    return res.status(201).json({ thread });
  } catch (error) {
    return next(error);
  }
}

export async function listThreadMessages(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const query = validateListMessages(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listMessages({
      userId: req.userId,
      threadId: thread.value,
      query: query.value,
    });
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function sendThreadMessage(req, res, next) {
  try {
    const thread = validateThreadId(req.params.threadId);
    if (!thread.ok) return badRequest(res, thread.errors);
    const body = validateSendMessage(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.sendMessage({
      userId: req.userId,
      threadId: thread.value,
      body: body.value.body,
    });
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}
