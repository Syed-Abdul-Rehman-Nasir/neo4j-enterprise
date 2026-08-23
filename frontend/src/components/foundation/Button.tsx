import type { ButtonHTMLAttributes, ReactNode } from 'react';
import styles from './Button.module.css';

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger';
interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> { variant?: Variant; size?: 'small' | 'default'; icon?: ReactNode; }
export function Button({ variant = 'secondary', size = 'default', icon, children, className = '', ...props }: ButtonProps) {
  return <button className={`${styles.button} ${styles[variant]} ${size === 'small' ? styles.small : ''} ${className}`} {...props}>{icon}{children}</button>;
}
