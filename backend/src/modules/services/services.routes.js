import { Router } from 'express';

import { requireAuth } from '../../shared/middleware/auth.middleware.js';
import { requireBackoffice } from '../../shared/middleware/backoffice.middleware.js';
import { requireServiceProvider } from '../../shared/middleware/service-provider.middleware.js';
import { imageUpload, mediaUpload } from '../../shared/utils/upload.js';
import * as c from './services.controller.js';

export const servicesPublicRouter = Router();
export const servicesProviderRouter = Router();
export const servicesRequestsRouter = Router();
export const servicesReviewsRouter = Router();
export const servicesAdminRouter = Router();

// Public discovery
servicesPublicRouter.get('/categories', c.listPublicCategories);
servicesPublicRouter.get('/search', c.searchPublic);
servicesPublicRouter.get('/providers/:providerId', c.getPublicProvider);
servicesPublicRouter.get('/offerings/:offeringId', c.getPublicOffering);
servicesPublicRouter.get('/providers/:providerId/reviews', c.listProviderReviews);
servicesPublicRouter.get('/offerings/:offeringId/reviews', c.listOfferingReviews);

// Auth user helpers
servicesPublicRouter.use(requireAuth);
servicesPublicRouter.post('/providers/:providerId/save', c.saveProvider);
servicesPublicRouter.delete('/providers/:providerId/save', c.unsaveProvider);
servicesPublicRouter.post('/offerings/:offeringId/save', c.saveOffering);
servicesPublicRouter.delete('/offerings/:offeringId/save', c.unsaveOffering);
servicesPublicRouter.get('/saved/providers', c.listSavedProviders);
servicesPublicRouter.get('/saved/offerings', c.listSavedOfferings);
servicesPublicRouter.get('/recent-views', c.listRecentViews);

// Provider onboarding + workspace
servicesProviderRouter.post(
  '/register',
  imageUpload.fields([
    { name: 'logoFile', maxCount: 1 },
    { name: 'coverFile', maxCount: 1 },
    { name: 'profileImageFile', maxCount: 1 },
  ]),
  c.registerProvider
);
servicesProviderRouter.post('/subscription/status', c.getProviderSubscriptionStatus);
servicesProviderRouter.post(
  '/subscription/requests/:requestId/respond-offer',
  c.respondProviderSubscriptionOffer
);

servicesProviderRouter.use(requireAuth, requireServiceProvider);
servicesProviderRouter.get('/workspace', c.getProviderWorkspace);
servicesProviderRouter.get('/profile', c.getProviderProfile);
servicesProviderRouter.patch(
  '/profile',
  imageUpload.fields([
    { name: 'logoFile', maxCount: 1 },
    { name: 'coverFile', maxCount: 1 },
  ]),
  c.updateProviderProfile
);
servicesProviderRouter.post('/offerings', imageUpload.array('mediaFiles', 10), c.createOffering);
servicesProviderRouter.patch(
  '/offerings/:offeringId',
  imageUpload.array('mediaFiles', 10),
  c.updateOffering
);
servicesProviderRouter.put('/offerings/:offeringId/pricing', c.replaceOfferingPricing);
servicesProviderRouter.post('/promotions', c.createPromotion);
servicesProviderRouter.post(
  '/portfolio',
  mediaUpload.single('mediaFile'),
  c.createPortfolioItem
);
servicesProviderRouter.delete('/portfolio/:portfolioId', c.deletePortfolioItem);
servicesProviderRouter.post('/category-suggestions', c.createCategorySuggestion);
servicesProviderRouter.get('/category-suggestions', c.listMyCategorySuggestions);
servicesProviderRouter.get('/requests', c.listProviderRequests);
servicesProviderRouter.post('/requests/:requestId/quotes', c.createQuote);
servicesProviderRouter.post('/requests/:requestId/status', c.updateProviderRequestStatus);

// Customer requests lifecycle
servicesRequestsRouter.use(requireAuth);
servicesRequestsRouter.post('/', imageUpload.array('attachmentFiles', 8), c.createServiceRequest);
servicesRequestsRouter.get('/mine', c.listMyRequests);
servicesRequestsRouter.get('/:requestId', c.getMyRequest);
servicesRequestsRouter.post('/:requestId/status', c.updateMyRequestStatus);
servicesRequestsRouter.post('/:requestId/quotes/:quoteId/respond', c.respondToQuote);

// Reviews
servicesReviewsRouter.get('/provider/:providerId', c.listProviderReviews);
servicesReviewsRouter.get('/offering/:offeringId', c.listOfferingReviews);
servicesReviewsRouter.use(requireAuth);
servicesReviewsRouter.post('/', c.createReview);

// Admin moderation
servicesAdminRouter.use(requireAuth, requireBackoffice);
servicesAdminRouter.get('/subscription-requests', c.listProviderSubscriptionRequests);
servicesAdminRouter.post(
  '/subscription-requests/:requestId/offer',
  c.adminSendSubscriptionOffer
);
servicesAdminRouter.post(
  '/subscription-requests/:requestId/reject',
  c.adminRejectSubscriptionRequest
);
servicesAdminRouter.post(
  '/subscription-requests/:requestId/confirm-cash-payment',
  c.adminConfirmSubscriptionCashPayment
);
servicesAdminRouter.get('/providers/pending', c.listPendingProviders);
servicesAdminRouter.patch('/providers/:providerId/status', c.adminUpdateProviderStatus);
servicesAdminRouter.get('/offerings/pending', c.listOfferingsForAdmin);
servicesAdminRouter.patch('/offerings/:offeringId/status', c.adminUpdateOfferingStatus);
servicesAdminRouter.get('/categories/suggestions', c.listCategorySuggestionsForAdmin);
servicesAdminRouter.patch(
  '/categories/suggestions/:suggestionId/review',
  c.adminReviewCategorySuggestion
);
servicesAdminRouter.get('/reports', c.listServiceReportsForAdmin);
servicesAdminRouter.patch('/reports/:reportId/review', c.adminReviewReport);
servicesAdminRouter.get('/requests', c.listRequestsForAdmin);
servicesAdminRouter.get('/stats', c.getAdminDashboardStats);
servicesAdminRouter.get('/settings', c.listModuleSettings);
servicesAdminRouter.put('/settings', c.upsertModuleSetting);
