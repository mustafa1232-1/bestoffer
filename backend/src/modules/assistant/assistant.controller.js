import * as service from "./assistant.service.js";
import * as aiService from "./assistant.ai.service.js";
import {
  validateAiConversationListQuery,
  validateAiConversationMessagesQuery,
  validateAiMemoryConsentBody,
  validateAiMemoryClearQuery,
  validateAiMemoryCreateBody,
  validateAiMemoryListQuery,
  validateAiMemoryUpdateBody,
  validateAiProfilePatchBody,
  validateAiTopicsQuery,
  validateAssistantAppSearchBody,
  validateAssistantWebSearchBody,
  validateChatBody,
  validateConfirmDraft,
  validateHomePreferencesBody,
  validateRecommendCommerceBody,
  validateRecommendJobsBody,
  validateSessionQuery,
} from "./assistant.validators.js";

export async function getCurrentSession(req, res, next) {
  try {
    const v = validateSessionQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const data = await service.getCurrentConversation(req.userId, {
      sessionId:
        req.query?.sessionId == null ? null : Number(req.query.sessionId),
      limit: req.query?.limit == null ? null : Number(req.query.limit),
    });
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function startNewSession(req, res, next) {
  try {
    const data = await service.startNewConversation(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function chat(req, res, next) {
  try {
    const body = req.body || {};
    const v = validateChatBody(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const data = await service.chat(req.userId, {
      message: body.message,
      sessionId: body.sessionId == null ? null : Number(body.sessionId),
      addressId: body.addressId == null ? null : Number(body.addressId),
      draftToken: body.draftToken || null,
      confirmDraft: body.confirmDraft === true,
      createDraft: body.createDraft === true,
      note: body.note,
    });
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function confirmDraft(req, res, next) {
  try {
    const v = validateConfirmDraft(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const data = await service.confirmDraft(req.userId, req.params.token, {
      sessionId: req.body?.sessionId == null ? null : Number(req.body.sessionId),
      addressId: req.body?.addressId == null ? null : Number(req.body.addressId),
      note: req.body?.note || null,
    });
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function getProfile(req, res, next) {
  try {
    const data = await service.getCustomerProfile(req.userId);
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function updateHomePreferences(req, res, next) {
  try {
    const body = req.body || {};
    const v = validateHomePreferencesBody(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const data = await service.saveHomePreferences(req.userId, {
      audience: body.audience,
      priority: body.priority,
      interests: body.interests,
      completed: body.completed,
    });
    res.json(data);
  } catch (e) {
    next(e);
  }
}

export async function recommendJobs(req, res, next) {
  try {
    const body = req.body || {};
    const v = validateRecommendJobsBody(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await aiService.recommendJobsForCustomer(req.userId, v.value);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function recommendCommerce(req, res, next) {
  try {
    const body = req.body || {};
    const v = validateRecommendCommerceBody(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await aiService.recommendCommerceForCustomer(req.userId, v.value);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function setAiMemoryConsent(req, res, next) {
  try {
    const v = validateAiMemoryConsentBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await aiService.setUserMemoryConsent({
      customerUserId: req.userId,
      consentFlags: v.value.consentFlags,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function getAiUserProfile(req, res, next) {
  try {
    const out = await aiService.getUserAiProfile({
      customerUserId: req.userId,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function updateAiUserProfile(req, res, next) {
  try {
    const v = validateAiProfilePatchBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await aiService.updateUserAiProfile({
      customerUserId: req.userId,
      dto: v.value,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function listAiConversations(req, res, next) {
  try {
    const v = validateAiConversationListQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await aiService.listUserAiConversations({
      customerUserId: req.userId,
      limit: v.value.limit,
      offset: v.value.offset,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function getAiConversation(req, res, next) {
  try {
    const v = validateAiConversationMessagesQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await aiService.getUserAiConversation({
      customerUserId: req.userId,
      conversationId: req.params.conversationId,
      messageLimit: v.value.messageLimit,
      beforeId: v.value.beforeId,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function listAiMemories(req, res, next) {
  try {
    const v = validateAiMemoryListQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await aiService.listUserAiMemories({
      customerUserId: req.userId,
      memoryType: v.value.memoryType,
      activeOnly: v.value.activeOnly,
      limit: v.value.limit,
      offset: v.value.offset,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function createAiMemory(req, res, next) {
  try {
    const v = validateAiMemoryCreateBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await aiService.createUserAiMemory({
      customerUserId: req.userId,
      dto: v.value,
    });
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function updateAiMemory(req, res, next) {
  try {
    const v = validateAiMemoryUpdateBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await aiService.updateUserAiMemory({
      customerUserId: req.userId,
      memoryId: req.params.memoryId,
      dto: v.value,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function deleteAiMemory(req, res, next) {
  try {
    const out = await aiService.deleteUserAiMemory({
      customerUserId: req.userId,
      memoryId: req.params.memoryId,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function clearAiMemories(req, res, next) {
  try {
    const v = validateAiMemoryClearQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await aiService.clearUserAiMemories({
      customerUserId: req.userId,
      activeOnly: v.value.activeOnly,
      memoryType: v.value.memoryType,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function listAiTopics(req, res, next) {
  try {
    const v = validateAiTopicsQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await aiService.listUserAiTopics({
      customerUserId: req.userId,
      limit: v.value.limit,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function appSearch(req, res, next) {
  try {
    const v = validateAssistantAppSearchBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await aiService.runAssistantAppSearch({
      customerUserId: req.userId,
      dto: v.value,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function webSearch(req, res, next) {
  try {
    const v = validateAssistantWebSearchBody(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await aiService.runAssistantWebSearch({
      customerUserId: req.userId,
      dto: v.value,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}
