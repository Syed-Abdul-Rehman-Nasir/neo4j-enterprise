import type { ReactNode } from 'react';
import styles from './Tooltip.module.css';
export function Tooltip({ content, children }: { content: ReactNode; children: ReactNode }) { return <span className={styles.wrap}>{children}<span role="tooltip" className={styles.tip}>{content}</span></span>; }
