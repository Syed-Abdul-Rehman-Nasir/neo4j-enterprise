import type { ReactNode } from 'react';
import styles from './Badge.module.css';

export function Badge({ children, tone = 'signal' }: { children: ReactNode; tone?: 'healthy' | 'warning' | 'critical' | 'signal' | 'neutral' }) {
  return <span className={`${styles.badge} ${tone !== 'neutral' ? styles[tone] : ''}`}>{children}</span>;
}
