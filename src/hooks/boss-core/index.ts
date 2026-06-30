/**
 * Boss Core — single source of truth for cross-module streams.
 * Every manager module (legal, hr, finance, ...) reads/writes via these
 * hooks and the underlying boss_* tables only. No parallel notification
 * systems are allowed.
 */
export * from './useBossNotifications';
export * from './useBossApprovals';
export * from './useBossTasks';
export * from './useBossAnnouncements';
export * from './useBossLiveStatus';
export * from './bossDispatch';
export type BossModule =
  | 'legal' | 'hr' | 'finance' | 'lead' | 'franchise' | 'reseller'
  | 'influencer' | 'marketing' | 'seo' | 'pro' | 'server' | 'demo'
  | 'ams' | 'security' | 'system';
