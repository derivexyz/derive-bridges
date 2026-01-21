use anchor_lang::prelude::*;
use anchor_spl::token::{self, Burn, Mint, MintTo, Token, TokenAccount};

declare_id!("BridgeXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX");

/// Maximum payload size for cross-chain messages
const MAX_PAYLOAD_SIZE: usize = 1024;

#[program]
pub mod oft_bridge {
    use super::*;

    /// Initialize the bridge configuration
    pub fn initialize(
        ctx: Context<Initialize>,
        destination_chain_id: u16,
        authority_bump: u8,
    ) -> Result<()> {
        let bridge_config = &mut ctx.accounts.bridge_config;
        bridge_config.authority = ctx.accounts.authority.key();
        bridge_config.destination_chain_id = destination_chain_id;
        bridge_config.authority_bump = authority_bump;
        bridge_config.paused = false;
        bridge_config.nonce = 0;

        msg!("Bridge initialized with destination chain ID: {}", destination_chain_id);
        Ok(())
    }

    /// Send tokens to the destination chain (burn on source)
    pub fn send_to_chain(
        ctx: Context<SendToChain>,
        destination_chain_id: u16,
        to_address: Vec<u8>,
        amount: u64,
    ) -> Result<()> {
        let bridge_config = &mut ctx.accounts.bridge_config;

        // Validate not paused
        require!(!bridge_config.paused, BridgeError::ContractPaused);

        // Validate destination chain
        require!(
            destination_chain_id == bridge_config.destination_chain_id,
            BridgeError::InvalidDestinationChain
        );

        // Validate recipient address
        require!(
            to_address.len() <= MAX_PAYLOAD_SIZE,
            BridgeError::PayloadTooLarge
        );

        // Burn tokens from sender
        let cpi_accounts = Burn {
            mint: ctx.accounts.token_mint.to_account_info(),
            from: ctx.accounts.user_token_account.to_account_info(),
            authority: ctx.accounts.user.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::burn(cpi_ctx, amount)?;

        // Increment nonce
        bridge_config.nonce += 1;
        let current_nonce = bridge_config.nonce;

        // Emit event for off-chain relayer to process
        emit!(SendToChainEvent {
            destination_chain_id,
            from: ctx.accounts.user.key(),
            to_address,
            amount,
            nonce: current_nonce,
        });

        msg!("Sent {} tokens to chain {} (nonce: {})", amount, destination_chain_id, current_nonce);
        Ok(())
    }

    /// Receive tokens from another chain (mint on destination)
    /// Note: In production, this would be called by a verified relayer/oracle
    pub fn receive_from_chain(
        ctx: Context<ReceiveFromChain>,
        source_chain_id: u16,
        from_address: Vec<u8>,
        amount: u64,
        nonce: u64,
    ) -> Result<()> {
        let bridge_config = &ctx.accounts.bridge_config;

        // Validate not paused
        require!(!bridge_config.paused, BridgeError::ContractPaused);

        // Validate source address
        require!(
            from_address.len() <= MAX_PAYLOAD_SIZE,
            BridgeError::PayloadTooLarge
        );

        // In production, add nonce tracking to prevent replay attacks
        // and verify the relayer signature/proof

        // Mint tokens to recipient
        let authority_seeds = &[
            b"authority",
            &[bridge_config.authority_bump],
        ];
        let signer = &[&authority_seeds[..]];

        let cpi_accounts = MintTo {
            mint: ctx.accounts.token_mint.to_account_info(),
            to: ctx.accounts.recipient_token_account.to_account_info(),
            authority: ctx.accounts.bridge_authority.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new_with_signer(cpi_program, cpi_accounts, signer);
        token::mint_to(cpi_ctx, amount)?;

        // Emit event
        emit!(ReceiveFromChainEvent {
            source_chain_id,
            from_address,
            to: ctx.accounts.recipient.key(),
            amount,
            nonce,
        });

        msg!("Received {} tokens from chain {} (nonce: {})", amount, source_chain_id, nonce);
        Ok(())
    }

    /// Set pause status (emergency stop)
    pub fn set_paused(ctx: Context<SetPaused>, paused: bool) -> Result<()> {
        let bridge_config = &mut ctx.accounts.bridge_config;
        bridge_config.paused = paused;

        emit!(PausedEvent { paused });
        msg!("Bridge paused status set to: {}", paused);
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + BridgeConfig::INIT_SPACE,
        seeds = [b"bridge_config"],
        bump
    )]
    pub bridge_config: Account<'info, BridgeConfig>,

    #[account(mut)]
    pub authority: Signer<'info>,

    /// CHECK: PDA used as mint authority
    #[account(
        seeds = [b"authority"],
        bump
    )]
    pub bridge_authority: UncheckedAccount<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SendToChain<'info> {
    #[account(
        mut,
        seeds = [b"bridge_config"],
        bump
    )]
    pub bridge_config: Account<'info, BridgeConfig>,

    #[account(mut)]
    pub token_mint: Account<'info, Mint>,

    #[account(
        mut,
        associated_token::mint = token_mint,
        associated_token::authority = user
    )]
    pub user_token_account: Account<'info, TokenAccount>,

    #[account(mut)]
    pub user: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct ReceiveFromChain<'info> {
    #[account(
        seeds = [b"bridge_config"],
        bump
    )]
    pub bridge_config: Account<'info, BridgeConfig>,

    #[account(mut)]
    pub token_mint: Account<'info, Mint>,

    #[account(
        mut,
        associated_token::mint = token_mint,
        associated_token::authority = recipient
    )]
    pub recipient_token_account: Account<'info, TokenAccount>,

    /// CHECK: Recipient can be any account
    pub recipient: UncheckedAccount<'info>,

    /// CHECK: PDA used as mint authority
    #[account(
        seeds = [b"authority"],
        bump = bridge_config.authority_bump
    )]
    pub bridge_authority: UncheckedAccount<'info>,

    #[account(mut)]
    pub relayer: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct SetPaused<'info> {
    #[account(
        mut,
        seeds = [b"bridge_config"],
        bump,
        has_one = authority
    )]
    pub bridge_config: Account<'info, BridgeConfig>,

    pub authority: Signer<'info>,
}

#[account]
#[derive(InitSpace)]
pub struct BridgeConfig {
    pub authority: Pubkey,
    pub destination_chain_id: u16,
    pub authority_bump: u8,
    pub paused: bool,
    pub nonce: u64,
}

#[event]
pub struct SendToChainEvent {
    pub destination_chain_id: u16,
    pub from: Pubkey,
    pub to_address: Vec<u8>,
    pub amount: u64,
    pub nonce: u64,
}

#[event]
pub struct ReceiveFromChainEvent {
    pub source_chain_id: u16,
    pub from_address: Vec<u8>,
    pub to: Pubkey,
    pub amount: u64,
    pub nonce: u64,
}

#[event]
pub struct PausedEvent {
    pub paused: bool,
}

#[error_code]
pub enum BridgeError {
    #[msg("Contract is paused")]
    ContractPaused,
    #[msg("Invalid destination chain")]
    InvalidDestinationChain,
    #[msg("Payload too large")]
    PayloadTooLarge,
    #[msg("Invalid nonce")]
    InvalidNonce,
}
