import type { ComponentPropsWithoutRef, ElementType, ReactNode } from 'react';
import styles from './Typography.module.css';

type TypographyProps<T extends ElementType> = { as?: T; children: ReactNode; className?: string } & Omit<ComponentPropsWithoutRef<T>, 'as' | 'children' | 'className'>;

export function Eyebrow({ children, className = '', ...props }: TypographyProps<'p'>) { return <p className={`${styles.eyebrow} ${className}`} {...props}>{children}</p>; }
export function Heading<T extends ElementType = 'h1'>({ as, children, className = '', ...props }: TypographyProps<T>) {
  const Component = as ?? 'h1';
  return <Component className={`${styles.heading} ${className}`} {...props}>{children}</Component>;
}
export function Body({ children, className = '', ...props }: TypographyProps<'p'>) { return <p className={`${styles.body} ${className}`} {...props}>{children}</p>; }
export function Muted({ children, className = '', ...props }: TypographyProps<'span'>) { return <span className={`${styles.muted} ${className}`} {...props}>{children}</span>; }
