import type { ReactNode } from 'react';
import { SearchX } from 'lucide-react';
import styles from './EmptyState.module.css';

export function EmptyState({ title, description, action }: { title: string; description: string; action?: ReactNode }) {
  return <div className={styles.empty}><SearchX size={28} aria-hidden="true" /><h3 className={styles.title}>{title}</h3><p>{description}</p>{action}</div>;
}
