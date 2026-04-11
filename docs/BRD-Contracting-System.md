# Contracting System Requirements

We need a system that handles all of our contracting paperwork from start to finish. Right now too much of this is manual — pulling up the right template, filling in the right fields, chasing signatures, making sure the right AP codes get used. People make mistakes because there's too many things to remember and no single place where it all lives.

The system should let our staff create contracts, generate the documents automatically, and get them through approval and out the door without anyone having to assemble a Word document by hand.

## What the business needs

We have two sides to our work. Sales is Ira and Steve bringing in new customers, writing proposals, setting up pricing and master service agreements. Operations is Tyler and the team issuing work orders to vendors, handling amendments, getting documents approved and sent out.

Both sides need to work in one place. Sales shouldn't have to hand off a folder to operations. When a customer is set up on the sales side, operations should be able to see everything they need — the MSA, the pricing, the locations — without asking anyone.

## Proposals

When sales is working a new customer or a renewal, they need to put together a proposal. The proposal includes which service package we're offering, which locations we're covering, and what the pricing looks like. The system should collect all of that and produce the proposal documents — the MSA, the location list, the fee schedule. Nobody should be building these in Word.

For a proposal we need to know the customer name and contact info, who can sign on their side, which of our service packages fits, what locations we're covering with addresses, and the monthly and onboarding rates. Some customers get one flat rate for everything, some get different rates depending on what type of facility the location is.

## Contracts

Most of what we produce are work orders. A work order says which vendor is doing what work at which location for which customer, how much it costs, and the billing codes. When you pick a vendor the system should fill in their legal name and address and all that automatically. Same with the location — pick it and the owner contact info comes in.

Each line item on a work order needs a description of the work, the dollar amount, and an AP cost code. Some customers use different AP codes than our standard list. The system should know which customers have special billing requirements and use the right codes automatically. Staff should not have to look that up or remember it.

Amendments work the same way but they reference a parent work order and have an amendment number. Vendor MSAs are agreements between us and the contractors we hire, which is different from the customer-facing MSAs on the sales side.

## TPA customers

This is Bill's biggest headache. Some of our customers are TPA organizations and they have their own document templates. If we send them our standard Decades template instead of their template, we have to start the whole signature process over. The system needs to know which customers have their own templates and use them automatically. The person creating the contract should not have to know or remember which template set goes with which customer.

## Work order numbers

Work order numbers come from the approval team, not from the person creating the contract. The person creating a contract saves it as a draft, it shows up in the approval queue, the approval team assigns the number, and when the person comes back to finish the contract the number is already there. The system needs to support saving drafts and coming back to them later. This is not optional — it's how the numbering process works.

## Approval

Nothing goes to a customer without someone on the approval team reviewing it first. The approval team needs to see all pending contracts in one place, be able to open and review the documents, approve them or send them back for corrections, assign work order numbers, and preview the email before it goes out. If a document fails to generate or send, the approval team needs to see that immediately, not find out later.

## Documents

All documents are generated from templates. The system fills in the data and produces the document. Work orders get an Exhibit A with the line items. Proposals get an Exhibit B with the location list, an Exhibit C with the fee schedule, and an Exhibit D for insurance. When it's time to send, everything gets converted to PDF and merged into one package.

Staff might need to regenerate a document after fixing some data. Old versions should be kept for the record but the working view should only show the current version. Only one version goes to the customer.

## Budgets

Each MSA has a budget. When a contract under that MSA gets signed, the amount should be committed against the budget automatically. Nobody should have to update a spreadsheet. The dashboard should show which MSAs are getting close to their budget limits.

## General expectations

Staff should be able to save their work at any point and come back to it later from any device. Every status change and approval should be logged so we can always answer the question "who did what and when." Records should never be permanently deleted — deactivate them so they can be recovered. The system should pick the right templates, apply the right AP codes, and fill in as much information as possible so staff can focus on the work, not the tool.
