import styles from './Spinner.module.css';
export function Spinner({ label = 'Loading' }: { label?: string }) { return <span className={styles.wrap}><span className={styles.spinner} aria-hidden="true" />{label}</span>; }
