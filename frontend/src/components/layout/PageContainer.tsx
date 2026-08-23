import type { ReactNode } from 'react';
import { Body, Eyebrow, Heading } from '../foundation';
import styles from './PageContainer.module.css';
export function PageContainer({ eyebrow, title, description, actions, children }: { eyebrow: string; title: string; description: string; actions?: ReactNode; children: ReactNode }) { return <section className={styles.page}><div className={styles.header}><div><Eyebrow>{eyebrow}</Eyebrow><Heading className={styles.title}>{title}</Heading><Body className={styles.description}>{description}</Body></div>{actions}</div>{children}</section>; }
