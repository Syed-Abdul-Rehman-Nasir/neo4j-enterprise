import type { LucideIcon } from 'lucide-react';
import styles from './Icon.module.css';
export function Icon({ icon: Component, size = 18, label }: { icon: LucideIcon; size?: number; label?: string }) { return <span className={styles.icon} aria-label={label} aria-hidden={label ? undefined : true}><Component size={size} /></span>; }
