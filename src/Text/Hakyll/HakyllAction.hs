-- | This is the module which exports @HakyllAction@.
module Text.Hakyll.HakyllAction
    ( HakyllAction (..)
    , createHakyllAction
    , createSimpleHakyllAction
    , createFileHakyllAction
    , chain
    , runHakyllAction
    , runHakyllActionIfNeeded
    ) where

import Control.Arrow
import Control.Category
import Control.Monad ((<=<), unless)
import Prelude hiding ((.), id)

import Text.Hakyll.File (toDestination, isFileMoreRecent)
import Text.Hakyll.HakyllMonad

-- | Type used for rendering computations that carry along dependencies.
data HakyllAction a b = HakyllAction
    { -- | Dependencies of the @HakyllAction@.
      actionDependencies :: [FilePath]
    , -- | URL pointing to the result of this @HakyllAction@.
      actionUrl          :: Either (Hakyll FilePath)
                                   (Hakyll FilePath -> Hakyll FilePath)
    , -- | The actual render function.
      actionFunction     :: a -> Hakyll b
    }

-- | Create a @HakyllAction@ from a function.
createHakyllAction :: (a -> Hakyll b)  -- ^ Function to execute.
                   -> HakyllAction a b
createHakyllAction f = id { actionFunction = f }

-- | Create a @HakyllAction@ from a simple @Hakyll@ value.
createSimpleHakyllAction :: Hakyll b -- ^ Hakyll value to pass on.
                         -> HakyllAction () b
createSimpleHakyllAction = createHakyllAction . const

-- | Create a @HakyllAction@ that operates on one file.
createFileHakyllAction :: FilePath          -- ^ File to operate on.
                       -> Hakyll b          -- ^ Value to pass on.
                       -> HakyllAction () b -- ^ The resulting action.
createFileHakyllAction path action = HakyllAction
    { actionDependencies = [path]
    , actionUrl          = Left $ return path
    , actionFunction     = const action
    }

-- | Run a @HakyllAction@ now.
runHakyllAction :: HakyllAction () a -- ^ Render action to run.
                -> Hakyll a          -- ^ Result of the action.
runHakyllAction action = actionFunction action ()

-- | Run a @HakyllAction@, but only when it is out-of-date. At this point, the
--   @actionUrl@ field must be set.
runHakyllActionIfNeeded :: HakyllAction () () -- ^ Action to run.
                        -> Hakyll ()          -- ^ Empty result.
runHakyllActionIfNeeded action = do
    url <- case actionUrl action of
        Left u  -> u
        Right _ -> error "No url when checking dependencies."
    destination <- toDestination url
    valid <- isFileMoreRecent destination $ actionDependencies action
    unless valid $ do logHakyll $ "Rendering " ++ destination
                      runHakyllAction action

-- | Chain a number of @HakyllAction@ computations.
chain :: [HakyllAction a a] -- ^ Actions to chain.
      -> HakyllAction a a   -- ^ Resulting action.
chain []   = id
chain list = foldl1 (>>>) list

instance Category HakyllAction where
    id = HakyllAction
        { actionDependencies = []
        , actionUrl          = Right id
        , actionFunction     = return
        }

    x . y = HakyllAction
        { actionDependencies = actionDependencies x ++ actionDependencies y
        , actionUrl          = case actionUrl x of
            Left ux  -> Left ux
            Right fx -> case actionUrl y of
                Left uy  -> Left (fx uy)
                Right fy -> Right (fx . fy)
        , actionFunction     = actionFunction x <=< actionFunction y
        }

instance Arrow HakyllAction where
    arr f = id { actionFunction = return . f }

    first x = x
        { actionFunction = \(y, z) -> do y' <- actionFunction x y
                                         return (y', z)
        }
