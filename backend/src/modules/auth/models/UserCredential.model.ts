import { Table, Column, Model, DataType, ForeignKey, BelongsTo } from 'sequelize-typescript';
import { User } from './User.model';

@Table({
    tableName: 'user_credentials',
    timestamps: true,
    underscored: true,
    comment: 'Separate table for sensitive credential data - enhanced security'[cite: 3]
})
export class UserCredential extends Model {
    @Column({
        type: DataType.UUID,
        primaryKey: true,
        defaultValue: DataType.UUIDV4
    })
    id!: string;

    @ForeignKey(() => User)
    @Column({
        type: DataType.UUID,
        allowNull: false,
        unique: true
    })
    userId!: string;

    @Column({
        type: DataType.STRING(255),
        allowNull: false,
        comment: 'bcrypt/argon2 hash'[cite: 3]
    })
    passwordHash!: string;

    @Column({
        type: DataType.STRING(255),
        comment: 'If not using built-in salt'[cite: 3]
    })
    passwordSalt?: string;

    @Column({
        type: DataType.DATE,
        defaultValue: DataType.NOW
    })
    passwordChangedAt!: Date;

    @Column({
        type: DataType.JSONB,
        comment: 'Store hashes of last N passwords to prevent reuse'[cite: 3]
    })
    passwordHistory?: any;

    @Column({
        type: DataType.BOOLEAN,
        defaultValue: false
    })
    mustChangePassword!: boolean;

    // Relationship back to User
    @BelongsTo(() => User)
    user!: User;
}