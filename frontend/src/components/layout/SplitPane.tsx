import type { ReactNode } from 'react';
import styles from './SplitPane.module.css';
export function SplitPane({ main, side }: { main: ReactNode; side: ReactNode }) { return <div className={styles.split}><div className={styles.pane}>{main}</div><aside className={styles.side}>{side}</aside></div>; }
