

# Azure DevOps – Complete Overview

## 1. What is Azure DevOps?

Azure DevOps is a set of modern, integrated services used by software teams to:

- Plan smarter

- Collaborate better

- Ship faster

- Manage source code

- Build and test applications

- Automate deployments

- Manage packages and artifacts

Azure DevOps services can be accessed through a web browser.

## 2. Former Name: VSTS

Azure DevOps was formerly known as **Visual Studio Team Services (VSTS)**.

Microsoft renamed VSTS to **Azure DevOps Services** in 2018.

| VSTS | Azure DevOps |

|---|---|

| Work | Azure Boards |

| Code | Azure Repos |

| Build & Release | Azure Pipelines |

| Test | Azure Test Plans |

| Packages | Azure Artifacts |

---

# 3. Azure vs Azure DevOps

## Microsoft Azure

Azure is Microsoft's cloud computing platform. It provides services such as:

- Virtual Machines

- Storage

- Networking

- Databases

- Kubernetes

- App Services

- Functions

- Monitoring

- Identity and Security

## Azure DevOps

Azure DevOps provides tools for the software development and DevOps lifecycle:

```text

Plan → Code → Build → Test → Release → Deploy → Improve

```

Azure DevOps integrates very well with Microsoft Azure, but Azure DevOps and Azure are separate products.

---

# 4. Azure DevOps Organization

An **Organization** is the top-level container in Azure DevOps.

Think of an organization as the **company/business-level environment**.

Example:

```text

ABC-Technologies

```

An organization can contain multiple projects.

### Organization manages

- Users and Groups

- Permissions and Security

- Billing

- Projects

- Policies

- Settings

- Extensions

- Auditing

Example:

```text

ABC-Technologies

│

├── Banking-Application

├── E-Commerce

└── HR-Portal

```

**ABC-Technologies = Organization**

---

# 5. Azure DevOps Projects

A **Project** is a workspace for a particular:

- Application

- Product

- Team

- Business initiative

Example:

```text

Organization

ABC-Technologies

│

├── Project 1: Banking-Application

├── Project 2: E-Commerce

└── Project 3: HR-Portal

```

Each project can have its own:

- Boards

- Repos

- Pipelines

- Test Plans

- Artifacts

- Teams

- Permissions

- Settings

### Organization vs Project

| Organization | Project |

|---|---|

| Top-level container | Workspace inside organization |

| Company/business level | Application/product/team level |

| Contains multiple projects | Contains DevOps resources |

| Organization-level settings | Project-level settings |

| Organization-level users/groups | Project permissions and teams |

### Easy memory

```text

Organization

     ↓

Projects

     ↓

DevOps Services

```

---

# 6. Azure DevOps Services

Azure DevOps has five major services:

1. **Azure Boards**

2. **Azure Repos**

3. **Azure Pipelines**

4. **Azure Test Plans**

5. **Azure Artifacts**

```text

                  Azure DevOps

                       │

       ┌───────────────┼───────────────┐

       │               │               │

     Boards           Repos         Pipelines

       │               │               │

       └───────────────┼───────────────┘

                       │

                   Test Plans

                       │

                    Artifacts

```

---

# 7. Azure Boards

Azure Boards is used to **plan, organize, assign, and track work**.

### Main features

- Epics

- Features

- User Stories

- Tasks

- Bugs

- Kanban Boards

- Backlogs

- Sprints

- Work Items

Example:

```text

Requirement

     ↓

Epic

     ↓

Feature

     ↓

User Story

     ↓

Task

     ↓

Developer

     ↓

Track Progress

```

### Main purpose

**Boards = Plan and Track Work**

---

# 8. Azure Repos

Azure Repos is used for **source-code management**.

It supports Git repositories.

### Main features

- Git repositories

- Branching

- Commit

- Push

- Pull

- Pull Requests

- Code Review

- Merge

- Compare Changes

Example:

```text

Banking-Application

│

├── frontend-repo

├── backend-repo

├── database-repo

└── infrastructure-repo

```

### Branching

```text

main

│

├── feature/login

├── feature/payment

└── bugfix/cart

```

### Git workflow

```text

Clone Repository

       ↓

Create Branch

       ↓

Write Code

       ↓

Commit

       ↓

Push

       ↓

Pull Request

       ↓

Code Review

       ↓

Merge

```

### Main purpose

**Repos = Store and Manage Source Code**

---

# 9. Azure Pipelines

Azure Pipelines automates:

- Build

- Test

- Release

- Deployment

It supports:

- Continuous Integration (CI)

- Continuous Delivery (CD)

- Continuous Deployment

- Triggers

- Stages

- Jobs

- Tasks

- Approvals

- Gates

## Continuous Integration

```text

Developer Pushes Code

        ↓

Pipeline Triggered

        ↓

Checkout Code

        ↓

Build

        ↓

Run Tests

        ↓

Create Artifact

```

## Continuous Delivery / Deployment

```text

Build

  ↓

Development

  ↓

QA

  ↓

Staging

  ↓

Production

```

### Main purpose

**Pipelines = Build, Test and Deploy Automatically**

---

# 10. Azure Test Plans

Azure Test Plans is used for **software testing and quality management**.

### Main features

- Test Cases

- Test Suites

- Test Execution

- Test Results

- Bug Tracking

- Test Analysis

### Example

```text

Test Case: Login

1. Open Login Page

2. Enter Username

3. Enter Password

4. Click Login

Expected Result:

User should successfully log in.

```

### Failed test workflow

```text

Execute Test

     ↓

Test Failed

     ↓

Create Bug

     ↓

Developer Fixes Bug

     ↓

Execute Test Again

```

### Main purpose

**Test Plans = Test and Validate the Application**

---

# 11. Azure Artifacts

Azure Artifacts is used for **package management and sharing reusable components**.

It can manage packages such as:

- NuGet

- npm

- Maven

- Python packages

Example:

```text

Common Library

      ↓

Azure Artifacts

      ↓

Application A

Application B

Application C

```

### Benefits

- Reuse packages

- Share libraries

- Central package management

- Save development time

- Avoid duplicate components

### Main purpose

**Artifacts = Store, Share and Reuse Packages**

---

# 12. Complete Azure DevOps Lifecycle

The five services work together:

```text

Business Requirement

        ↓

Azure Boards

        ↓

Azure Repos

        ↓

Azure Pipelines

        ↓

Azure Test Plans

        ↓

Azure Artifacts

        ↓

Deployment

        ↓

Development

        ↓

QA

        ↓

Staging

        ↓

Production

```

The process continuously repeats.

---

# 13. Real-World Example – Banking Application

Suppose ABC Technologies is developing an **Online Banking Application**.

## Step 1 – Organization

```text

ABC-Technologies

```

## Step 2 – Project

```text

Banking-Application

```

## Step 3 – Boards

Create:

```text

User Story:

Implement Online Payment

```

Break it into tasks:

```text

Payment API

Payment UI

Database Changes

Unit Tests

```

## Step 4 – Repos

Developer creates:

```text

feature/payment

```

Workflow:

```text

Write Code

    ↓

Commit

    ↓

Push

    ↓

Pull Request

    ↓

Code Review

    ↓

Merge

```

## Step 5 – Pipelines

```text

Checkout Code

      ↓

Build

      ↓

Unit Tests

      ↓

Code Quality Check

      ↓

Package

```

## Step 6 – Test Plans

```text

Test

 ↓

Pass → Continue

 ↓

Fail → Create Bug

```

## Step 7 – Artifacts

```text

Build Package

     ↓

Azure Artifacts

     ↓

Reuse Package

```

## Step 8 – Deployment

```text

Development

     ↓

QA

     ↓

Staging

     ↓

Production

```

---

# 14. Azure DevOps Server

Azure DevOps has two main deployment models.

## Azure DevOps Services

Cloud-based, Microsoft-hosted offering.

```text

Team

 ↓

Internet / Browser

 ↓

Azure DevOps Services

 ↓

Projects

```

Benefits:

- Microsoft-hosted

- Cloud-based

- Less infrastructure management

- Easy access

- Microsoft manages the service infrastructure

## Azure DevOps Server

Azure DevOps Server is the **self-hosted/on-premises** option.

```text

Company Network

      ↓

Azure DevOps Server

      ↓

Projects

      ↓

Repos / Boards / Pipelines / Tests / Artifacts

```

Organizations may choose it when they need to maintain DevOps infrastructure and data within their own environment.

### Cloud vs On-Premises

| Azure DevOps Services | Azure DevOps Server |

|---|---|

| Microsoft-hosted | Self-hosted |

| Cloud-based | On-premises/private environment |

| Microsoft manages infrastructure | Organization manages infrastructure |

| Less infrastructure administration | More infrastructure administration |

---

# 15. Overall Azure DevOps Hierarchy

```text

                    ORGANIZATION

                         │

                  ABC-Technologies

                         │

          ┌──────────────┼──────────────┐

          ↓              ↓              ↓

       PROJECT         PROJECT        PROJECT

       Banking       E-Commerce        HR

          │              │              │

          ↓              ↓              ↓

       BOARDS          BOARDS          BOARDS

       REPOS           REPOS           REPOS

       PIPELINES       PIPELINES       PIPELINES

       TEST PLANS      TEST PLANS      TEST PLANS

       ARTIFACTS       ARTIFACTS       ARTIFACTS

```

---

# 16. Five Services – Easy Memory Trick

| Service | Purpose | Easy Question |

|---|---|---|

| **Boards** | Plan and track work | What should we do? |

| **Repos** | Source control | Where is our code? |

| **Pipelines** | CI/CD | How do we build and deploy? |

| **Test Plans** | Testing | Does it work? |

| **Artifacts** | Package management | Where do we store packages? |

---

# 17. Simple Explanation for Students

> **Azure DevOps is a collection of integrated tools that helps software teams plan work, manage source code, automatically build and deploy applications, test them, and manage reusable packages.**

### Complete flow

```text

PLAN

 ↓

Boards

 ↓

CODE

 ↓

Repos

 ↓

BUILD & DEPLOY

 ↓

Pipelines

 ↓

TEST

 ↓

Test Plans

 ↓

PACKAGE

 ↓

Artifacts

 ↓

DEPLOY

 ↓

Production

```

---

# 18. Interview Quick Revision

### What is Azure DevOps?

Azure DevOps is a collection of integrated services used for planning, source-code management, CI/CD, testing, and package management.

### What is an Organization?

The top-level container in Azure DevOps that can contain multiple projects.

### What is a Project?

A workspace for an application, product, team, or business initiative.

### What is Azure Boards?

Used to plan and track work items.

### What is Azure Repos?

Used to manage source code and Git repositories.

### What is Azure Pipelines?

Used to automate build, test, release, and deployment.

### What is Azure Test Plans?

Used to create and execute test cases and manage testing.

### What is Azure Artifacts?

Used to store, manage, and share software packages.

### Azure DevOps Services vs Server?

**Services = Microsoft-hosted cloud offering**

**Server = Self-hosted/on-premises offering**

---

# 19. Final Cheat Sheet

```text

                     AZURE DEVOPS

                           │

                    ORGANIZATION

                           │

                       PROJECT

                           │

       ┌───────────┬───────┼───────┬───────────┐

       ↓           ↓       ↓       ↓           ↓

     BOARDS      REPOS  PIPELINES  TEST      ARTIFACTS

       ↓           ↓       ↓       ↓           ↓

      PLAN        CODE    CI/CD   TESTING    PACKAGES

       │           │       │       │           │

       └───────────┴───────┴───────┴───────────┘

                           ↓

                       DEPLOYMENT

                           ↓

                  DEV → QA → STAGING

                           ↓

                       PRODUCTION

```

## Memory Trick

**Organization → Project → Boards → Repos → Pipelines → Test Plans → Artifacts → Deployment**

